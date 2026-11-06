// Things on the track that can be shot: gates, barrels, crates, enemies, boss.
// Everything uses native Doom sizes (scale 1) - the world is built around them.

class RunnerTarget : Actor
{
	double hp, maxhp;
	bool dead;
	int hitFlash;

	Default
	{
		-SOLID
		+SHOOTABLE
		+NOBLOOD
		+DONTTHRUST
		+NOTAUTOAIMED
		Health 1000;
	}

	virtual void OnShot(double d, Actor src) {}
	virtual double WalkSpeed() { return 0; }

	RunnerHandler H() { return RunnerHandler.Get(); }

	// every hit (Doom/Brutal Doom hitscan, rockets, plasma, ...) ends up here;
	// we convert it into our own damage and never lose real health
	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		if (dead) return 0;
		let h = H();
		if (!h) return 0;
		double d = h.ResolveDamage(inflictor, source, damage, mod, flags);
		if (d > 0) OnShot(d, source);
		return 0;
	}

	bool Touches(Actor a, double pad = 0)
	{
		return a && abs(a.pos.x - pos.x) < radius + a.radius + pad
			&& abs(a.pos.y - pos.y) < radius + a.radius + pad;
	}

	// defense levels: the world comes towards the standing player
	bool Approach(RunnerHandler h)
	{
		if (!h.defense || h.phase != 1 || dead) return false;
		SetOrigin(pos - (0, h.approachSpeed + WalkSpeed(), 0), true);
		let pm = players[consoleplayer].mo;
		if (pm && pos.y < pm.pos.y - 260)
		{
			Destroy();
			return true;
		}
		return false;
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		if (hitFlash > 0) hitFlash--;
	}
}

// ---------------------------------------------------------------- gates
class RGate : RunnerTarget
{
	int kind;     // 0 damage, 1 fire rate, 2 range, 3 soldiers, 4 health
	double value;
	bool used;

	Default
	{
		Radius 68;
		Height 82;
		XScale 1.1;
		YScale 0.85;
		RenderStyle "Translucent";
		Alpha 1.0;
	}

	States
	{
	Spawn:
		RGAT A -1;
		stop;
	}

	clearscope double StepSize()
	{
		static const double st[] = { 0.02, 0.05, 0.1, 0.2, 0.25 };
		return st[kind];
	}

	clearscope double MaxValue()
	{
		static const double mx[] = { 1.0, 2.0, 6.0, 8.0, 20.0 };
		return mx[kind];
	}

	clearscope int IntVal() { return int(floor(value)); }

	clearscope String KindName()
	{
		return StringTable.Localize(String.Format("$RR_G%d", kind));
	}

	clearscope String ValueText()
	{
		String s;
		if (kind >= 3)
		{
			int n = IntVal();
			s = n >= 0 ? String.Format("+%d", n) : String.Format("%d", n);
		}
		else if (kind == 0) s = String.Format("%+.2f", abs(value) < 0.005 ? 0.0 : value);
		else s = String.Format("%+.1f", abs(value) < 0.05 ? 0.0 : value);
		if (StringTable.Localize("$RR_LANGID") == "de") s.Replace(".", ",");
		return s;
	}

	override void OnShot(double d, Actor src)
	{
		if (used) return;
		value = min(value + StepSize(), MaxValue());
		hitFlash = 3;
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		frame = (value >= 0) ? 0 : 1;
		Scale.Y = 0.85 + (hitFlash > 0 ? 0.04 : 0);
		if (used)
		{
			A_FadeOut(0.08);
			return;
		}
		let h = H();
		if (!h || h.phase != 1) return;
		if (Approach(h)) return;
		let pm = players[consoleplayer].mo;
		if (pm && pos.y < pm.pos.y - 40)
		{
			// missed gate: just fade away
			used = true;
			bSHOOTABLE = false;
			return;
		}
		if (pm && pm.pos.y >= pos.y - 6 && pm.pos.y - pos.y < 40 && abs(pm.pos.x - pos.x) < radius)
		{
			used = true;
			bSHOOTABLE = false;
			h.ApplyGate(self);
		}
	}
}

// -------------------------------------------------------------- barrels
class RBarrel : RunnerTarget
{
	RRecruit rider;

	Default
	{
		Radius 16;
		Height 32;
	}

	States
	{
	Spawn:
		BAR1 AB 6;
		loop;
	}

	override void OnShot(double d, Actor src)
	{
		if (dead) return;
		hp -= d;
		hitFlash = 3;
		if (hp <= 0) Smash(true);
	}

	void Smash(bool byShot)
	{
		if (dead) return;
		dead = true;
		let h = H();
		if (byShot)
		{
			if (h) h.AddCash(max(1, int(maxhp * 0.6 + 0.5)), pos + (0, 0, 40));
			if (rider) rider.Drop();
		}
		else if (rider) rider.Destroy();
		rider = null;
		// real Doom barrel explosion (Brutal Doom's when loaded); it hurts
		// everything standing close by
		if (h)
		{
			h.SpawnDeath('ExplosiveBarrel', pos, 270, false);
			h.Splash(pos, 105, 3 + h.stage, self);
		}
		Destroy();
	}

	override void Tick()
	{
		Super.Tick();
		if (dead || bDestroyed) return;
		double s = hitFlash > 0 ? 1.1 : 1.0;
		Scale = (s, s);
		let h = H();
		if (!h || h.phase != 1) return;
		if (Approach(h)) return;
		let pm = players[consoleplayer].mo;
		if (Touches(pm, -4))
		{
			h.DamagePlayer(2);
			Smash(false);
			return;
		}
		for (int i = 0; i < h.allies.Size(); i++)
		{
			let a = h.allies[i];
			if (a && !a.dying && Touches(a, -4))
			{
				a.AllyDie();
				OnShot(2, null);
				return;
			}
		}
	}
}

// --------------------------------------------------------------- crates
// wooden crate (Doom II CRATE texture): no explosion, but random loot
class RCrate : RunnerTarget
{
	Default
	{
		Radius 22;
		Height 45;
		Scale 0.7;
	}

	States
	{
	Spawn:
		RCRT A -1;
		stop;
	Alt:
		RCRT B -1;
		stop;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		if (Random(0, 1)) SetStateLabel("Alt");
	}

	override void OnShot(double d, Actor src)
	{
		if (dead) return;
		hp -= d;
		hitFlash = 3;
		if (hp <= 0) Smash(true);
	}

	void Smash(bool byShot)
	{
		if (dead) return;
		dead = true;
		let h = H();
		if (byShot && h)
		{
			h.AddCash(max(1, int(maxhp * 0.4 + 0.5)), pos + (0, 0, 50));
			h.RollDrop(pos);
		}
		for (int i = 0; i < 10; i++)
		{
			let c = Actor.Spawn("RChunk", pos + (FRandom(-14, 14), 0, FRandom(8, 40)));
			if (c) c.Vel = (FRandom(-4, 4), FRandom(-2, 5), FRandom(3, 7));
		}
		A_StartSound("plats/pt1_stop", CHAN_AUTO, 0, RR_VOL);
		Destroy();
	}

	override void Tick()
	{
		Super.Tick();
		if (dead || bDestroyed) return;
		double s = hitFlash > 0 ? 0.76 : 0.7;
		Scale = (s, s);
		let h = H();
		if (!h || h.phase != 1) return;
		if (Approach(h)) return;
		let pm = players[consoleplayer].mo;
		if (Touches(pm, -4))
		{
			h.DamagePlayer(2);
			Smash(false);
			return;
		}
		for (int i = 0; i < h.allies.Size(); i++)
		{
			let a = h.allies[i];
			if (a && !a.dying && Touches(a, -4))
			{
				a.AllyDie();
				OnShot(2, null);
				return;
			}
		}
	}
}

// -------------------------------------------------------------- enemies
// Like in the arcade shooters: enemies never shoot, they charge at you.
// Contact costs health. Subclasses: sergeant (tough, slow), imp (fast), boss.
class REnemy : RunnerTarget
{
	bool leader;      // first of a group: triggers the "attack" banner
	bool announced;
	double lastHit;   // for overkill gibs

	Default
	{
		Radius 20;
		Height 56;
	}

	States
	{
	Spawn:
		POSS AB 10;
		loop;
	See:
		POSS ABCD 5;
		loop;
	Death:
		POSS H 5;
		POSS I 5;
		POSS J 5;
		POSS K 5;
		POSS L 70;
		POSS L 1 A_FadeOut(0.05);
		wait;
	XDeath:
		POSS M 5;
		POSS N 5;
		POSS O 5;
		POSS P 5;
		POSS Q 5;
		POSS R 5;
		POSS S 5;
		POSS T 5;
		POSS U 70;
		POSS U 1 A_FadeOut(0.05);
		wait;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		Angle = 270;
	}

	virtual int ContactDamage() { return 1; }
	virtual double KillReward() { return 0.8; }
	virtual Name GoreClass() { return 'ZombieMan'; }
	virtual Sound DeathSoundName() { return "grunt/death"; }
	virtual Sound HitSoundName() { return "grunt/attack"; }
	virtual double ChaseDist() { return 750; }
	override double WalkSpeed() { return 0.9; }

	override void OnShot(double d, Actor src)
	{
		if (dead) return;
		lastHit = d;
		hp -= d;
		hitFlash = 3;
		if (hp <= 0) Kill(true);
	}

	virtual void Kill(bool byShot)
	{
		if (dead) return;
		dead = true;
		bSHOOTABLE = false;
		let h = H();
		if (byShot && h)
		{
			h.AddCash(max(1, int(maxhp * KillReward() + 0.5)), pos + (0, 0, 64));
			h.AddKill(pos + (0, 0, 64));
		}
		// overkill (big hit, rocket, barrel ...) blows them to pieces
		static const int goreChance[] = { 15, 30, 50, 75 };
		int gore = clamp(CVar.FindCVar('rr_gore').GetInt(), 0, 3);
		bool extreme = byShot && (lastHit >= maxhp * 0.75 || Random(0, 99) < goreChance[gore]);
		if (h && h.bdMode && GoreClass() != 'None')
		{
			// let Brutal Doom do the dying: real BD monster, killed on the spot
			if (h.SpawnDeath(GoreClass(), pos, Angle, extreme))
			{
				A_SetRenderStyle(0, STYLE_None);
				Destroy();
				return;
			}
		}
		if (extreme && FindState("XDeath"))
		{
			SetStateLabel("XDeath");
			A_StartSound("misc/gibbed", CHAN_VOICE, 0, RR_VOL);
		}
		else
		{
			SetStateLabel("Death");
			A_StartSound(DeathSoundName(), CHAN_VOICE, 0, RR_VOL);
		}
	}

	override void Tick()
	{
		Super.Tick();
		if (dead || bDestroyed) return;
		Angle = 270;
		let h = H();
		if (!h || h.phase != 1) return;
		let pm = players[consoleplayer].mo;
		if (!pm) return;
		double dy = pos.y - pm.pos.y;
		bool walking = false;
		if (h.defense)
		{
			if (Approach(h)) return;
			walking = true;
		}
		else if (dy < ChaseDist() && dy > -80)
		{
			// charge: walk towards the player, drifting a little towards his lane
			double dx = clamp((pm.pos.x - pos.x) * 0.01, -0.35, 0.35);
			SetOrigin(pos + (dy < 400 ? dx : 0, -WalkSpeed(), 0), true);
			walking = true;
		}
		if (walking && InStateSequence(CurState, SpawnState)) SetStateLabel("See");

		if (leader && !announced && dy < 1000)
		{
			announced = true;
			h.ShowBanner(self is "RBoss" ? StringTable.Localize("$RR_BOSSBANNER") : (h.defense ? StringTable.Localize("$RR_HORDE") : ""));
		}
		if (Touches(pm, -4))
		{
			A_StartSound(HitSoundName(), CHAN_WEAPON, 0, RR_VOL);
			h.DamagePlayer(ContactDamage());
			if (ContactDamage() < 50) Kill(false);
			return;
		}
		for (int i = 0; i < h.allies.Size(); i++)
		{
			let a = h.allies[i];
			if (a && !a.dying && Touches(a, -4))
			{
				a.AllyDie();
				OnShot(2, null);
				if (dead) return;
			}
		}
	}
}

class RSergeant : REnemy
{
	States
	{
	Spawn:
		SPOS AB 10;
		loop;
	See:
		SPOS ABCD 6;
		loop;
	Death:
		SPOS H 5;
		SPOS I 5;
		SPOS J 5;
		SPOS K 5;
		SPOS L 70;
		SPOS L 1 A_FadeOut(0.05);
		wait;
	XDeath:
		SPOS M 5;
		SPOS N 5;
		SPOS O 5;
		SPOS P 5;
		SPOS Q 5;
		SPOS R 5;
		SPOS S 5;
		SPOS T 5;
		SPOS U 70;
		SPOS U 1 A_FadeOut(0.05);
		wait;
	}

	override Name GoreClass() { return 'ShotgunGuy'; }
	override int ContactDamage() { return 2; }
	override double WalkSpeed() { return 0.7; }
	override Sound HitSoundName() { return "shotguy/attack"; }
}

class RImp : REnemy
{
	States
	{
	Spawn:
		TROO AB 10;
		loop;
	See:
		TROO ABCD 4;
		loop;
	Death:
		TROO I 6;
		TROO J 6;
		TROO K 6;
		TROO L 6;
		TROO M 70;
		TROO M 1 A_FadeOut(0.05);
		wait;
	XDeath:
		TROO N 5;
		TROO O 5;
		TROO P 5;
		TROO Q 5;
		TROO R 5;
		TROO S 5;
		TROO T 5;
		TROO U 70;
		TROO U 1 A_FadeOut(0.05);
		wait;
	}

	override Name GoreClass() { return 'DoomImp'; }
	override int ContactDamage() { return 2; }
	override double WalkSpeed() { return 1.4; }
	override double ChaseDist() { return 900; }
	override Sound DeathSoundName() { return "imp/death"; }
	override Sound HitSoundName() { return "imp/melee"; }
}

// ------------------------------------------------------------ new monsters
class RDemon : REnemy
{
	Default
	{
		Radius 28;
		Height 56;
	}

	States
	{
	Spawn:
		SARG AB 10;
		loop;
	See:
		SARG ABCD 3;
		loop;
	Death:
		SARG I 6;
		SARG J 6;
		SARG K 5;
		SARG L 5;
		SARG M 5;
		SARG N 70;
		SARG N 1 A_FadeOut(0.05);
		wait;
	}

	override Name GoreClass() { return 'Demon'; }
	override int ContactDamage() { return 3; }
	override double WalkSpeed() { return 1.6; }
	override double ChaseDist() { return 900; }
	override Sound DeathSoundName() { return "demon/death"; }
	override Sound HitSoundName() { return "demon/melee"; }
}

class RLostSoul : REnemy
{
	Default
	{
		Radius 16;
		Height 56;
		+NOGRAVITY
		+FLOAT
	}

	States
	{
	Spawn:
		SKUL AB 5 Bright;
		loop;
	See:
		SKUL AB 3 Bright;
		loop;
	Death:
		SKUL F 5 Bright;
		SKUL G 5 Bright;
		SKUL H 5 Bright;
		SKUL I 5 Bright;
		SKUL J 5;
		SKUL K 5;
		stop;
	}

	override Name GoreClass() { return 'LostSoul'; }
	override int ContactDamage() { return 2; }
	override double WalkSpeed() { return 2.0; }
	override double ChaseDist() { return 1000; }
	override Sound DeathSoundName() { return "skull/death"; }
	override Sound HitSoundName() { return "skull/melee"; }

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed || dead) return;
		SetZ(18 + 8 * sin(level.maptime * 9.0 + pos.x));
	}
}

// ------------------------------------------------------------ bosses
// the boss slowly stomps towards you - kill him before he arrives
class RBoss : REnemy
{
	override Name GoreClass() { return 'None'; }
	override int ContactDamage() { return 99; }
	override double ChaseDist() { return 650; }
	override double KillReward() { return 0.4; }
	int chunksPaid;

	// tough bosses: every 10% of his health you shoot off pays souls, even if he gets you
	override void OnShot(double d, Actor src)
	{
		Super.OnShot(d, src);
		let h = H();
		if (!h || maxhp <= 0) return;
		int chunks = min(10, int((maxhp - max(hp, 0.0)) / maxhp * 10));
		while (chunksPaid < chunks)
		{
			chunksPaid++;
			h.AddCash(max(1, int(maxhp * 0.04 + 0.5)), pos + (FRandom(-30, 30), 0, Height + 10));
		}
	}
	virtual double BossSpeed() { return 0.5; }
	override double WalkSpeed()
	{
		// defense: the world moves at approachSpeed; the boss itself only creeps
		let h = H();
		if (h && h.defense)
		{
			let pm = players[consoleplayer].mo;
			if (pm && pos.y - pm.pos.y < 600) return BossSpeed() - h.approachSpeed;
			return 0;
		}
		return BossSpeed();
	}
}

class RBossKnight : RBoss
{
	Default { Radius 24; Height 64; }
	States
	{
	Spawn: BOS2 AB 10; loop;
	See: BOS2 ABCD 6; loop;
	Death: BOS2 I 8; BOS2 J 8; BOS2 K 8; BOS2 L 8; BOS2 M 8; BOS2 N 8; BOS2 O 70; BOS2 O 1 A_FadeOut(0.05); wait;
	}
	override Name GoreClass() { return 'HellKnight'; }
	override double BossSpeed() { return 0.6; }
	override Sound DeathSoundName() { return "knight/death"; }
	override Sound HitSoundName() { return "baron/melee"; }
}

class RBossBaron : RBoss
{
	Default { Radius 24; Height 64; }
	States
	{
	Spawn: BOSS AB 10; loop;
	See: BOSS ABCD 6; loop;
	Death: BOSS I 8; BOSS J 8; BOSS K 8; BOSS L 8; BOSS M 8; BOSS N 8; BOSS O 70; BOSS O 1 A_FadeOut(0.05); wait;
	}
	override Name GoreClass() { return 'BaronOfHell'; }
	override double BossSpeed() { return 0.55; }
	override Sound DeathSoundName() { return "baron/death"; }
	override Sound HitSoundName() { return "baron/melee"; }
}

class RBossCyber : RBoss
{
	Default { Radius 40; Height 110; }
	States
	{
	Spawn: CYBR AB 10; loop;
	See: CYBR ABCD 6; loop;
	Death: CYBR H 10; CYBR I 10; CYBR J 10; CYBR K 10; CYBR L 10; CYBR M 10; CYBR N 10; CYBR O 10; CYBR P 70; CYBR P 1 A_FadeOut(0.05); wait;
	}
	override Name GoreClass() { return 'Cyberdemon'; }
	override double BossSpeed() { return 0.45; }
	override Sound DeathSoundName() { return "cyber/death"; }
	override Sound HitSoundName() { return "cyber/hoof"; }
}

class RBossFatso : RBoss
{
	Default { Radius 48; Height 64; }
	States
	{
	Spawn: FATT AB 15; loop;
	See: FATT ABCDEF 5; loop;
	Death: FATT K 6; FATT L 6; FATT M 6; FATT N 6; FATT O 6; FATT P 6; FATT Q 6; FATT R 6; FATT S 6; FATT T 70; FATT T 1 A_FadeOut(0.05); wait;
	}
	override Name GoreClass() { return 'Fatso'; }
	override double BossSpeed() { return 0.4; }
	override Sound DeathSoundName() { return "fatso/death"; }
	override Sound HitSoundName() { return "fatso/attack"; }
}

class RBossSpider : RBoss
{
	Default { Radius 100; Height 100; Scale 0.85; }
	States
	{
	Spawn: SPID AB 10; loop;
	See: SPID ABCDEF 4; loop;
	Death: SPID J 10; SPID K 10; SPID L 10; SPID M 10; SPID N 10; SPID O 10; SPID P 10; SPID Q 10; SPID R 10; SPID S 70; SPID S 1 A_FadeOut(0.05); wait;
	}
	override Name GoreClass() { return 'SpiderMastermind'; }
	override double BossSpeed() { return 0.5; }
	override Sound DeathSoundName() { return "spider/death"; }
	override Sound HitSoundName() { return "spider/attack"; }
}
