// Bullets, allies, recruits, pickups, effects

// Ally bullet (allies keep simple bullets so they never hit the player)
class RBullet : Actor
{
	double dmg, maxDist, startY;
	int age;

	Default
	{
		Radius 4;
		Height 5;
		Speed 26;
		Damage 0;
		Projectile;
		+BRIGHT
		Scale 0.7;
	}

	States
	{
	Spawn:
		RBUL A -1;
		stop;
	Death:
		RBUL B 2;
		RBUL C 3;
		stop;
	}

	override int SpecialMissileHit(Actor victim)
	{
		let t = RunnerTarget(victim);
		if (t && !t.dead)
		{
			t.OnShot(dmg, target);
			return 0;
		}
		return 1;
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		age++;
		if (InStateSequence(CurState, SpawnState))
		{
			double refY = target ? target.pos.y : startY + age * 4;
			if (pos.y - refY > maxDist || age > 200) Destroy();
		}
	}
}

// purely visual tracer streak for the player's hitscan shots (vanilla mode)
class RTracerFX : Actor
{
	int life;

	Default
	{
		+NOINTERACTION
		+BRIGHT
		RenderStyle "Add";
		Scale 0.6;
	}

	States
	{
	Spawn:
		RBUL A -1;
		stop;
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		if (--life <= 0) Destroy();
	}
}

class REBullet : Actor
{
	int age;

	Default
	{
		Radius 5;
		Height 6;
		Speed 8;
		Damage 0;
		Projectile;
		+BRIGHT
		Scale 1.0;
	}

	States
	{
	Spawn:
		REBU A -1;
		stop;
	Death:
		REBU B 4;
		stop;
	}

	override int SpecialMissileHit(Actor victim)
	{
		if (victim is "PlayerPawn")
		{
			let h = RunnerHandler.Get();
			if (h) h.DamagePlayer(1);
			return 0;
		}
		return 1;
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		if (++age > 260) { Destroy(); return; }
		if (!InStateSequence(CurState, SpawnState)) return;
		// allies are not shootable (so the player's hitscan passes them): check by hand
		let h = RunnerHandler.Get();
		if (!h) return;
		for (int i = 0; i < h.allies.Size(); i++)
		{
			let a = h.allies[i];
			if (a && !a.dying && abs(a.pos.x - pos.x) < 14 && abs(a.pos.y - pos.y) < 14)
			{
				a.Hurt();
				ExplodeMissile(null, null);
				return;
			}
		}
	}
}

class RAlly : Actor
{
	int hp;
	double fireAcc;
	bool dying;

	Default
	{
		Radius 14;
		Height 50;
		Health 1;
		-SOLID
		+NOBLOOD
		+NOGRAVITY
		+DONTTHRUST
		+NOTAUTOAIMED
		Translation "112:127=[110,170,255]:[0,25,110]";
	}

	States
	{
	Spawn:
		PLAY A -1;
		stop;
	See:
		PLAY ABCD 4;
		loop;
	Death:
		PLAY H 5;
		PLAY I 5;
		PLAY J 5;
		PLAY K 5;
		PLAY L 5;
		PLAY M 5;
		PLAY N 30;
		PLAY N 1 A_FadeOut(0.06);
		wait;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		hp = 2;
		fireAcc = FRandom(0, 1);
	}

	void Hurt()
	{
		hp--;
		if (hp <= 0) AllyDie();
	}

	void AllyDie()
	{
		if (dying) return;
		dying = true;
		let h = RunnerHandler.Get();
		if (h) h.AllyDied(self);
		SetStateLabel("Death");
		A_StartSound("grunt/death", CHAN_VOICE, 0, 0.5 * RR_VOL);
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed || dying) return;
		let h = RunnerHandler.Get();
		let pm = players[consoleplayer].mo;
		if (!h || !pm) return;
		int idx = h.allies.Find(self);
		if (idx >= h.allies.Size()) return;

		Vector2 off = RunnerHandler.SlotOffset(idx);
		double tx = clamp(pm.pos.x + off.x, -RR_HALF, RR_HALF);
		double ty = pm.pos.y + off.y;
		SetOrigin((pos.x + (tx - pos.x) * 0.2, pos.y + (ty - pos.y) * 0.3, pm.pos.z), true);
		Angle = 90;

		State see = ResolveState("See");
		bool moving = h.phase == 1 && (h.runSpeed > 0 || abs(tx - pos.x) > 3);
		if (moving && InStateSequence(CurState, SpawnState)) SetState(see);
		else if (!moving && InStateSequence(CurState, see)) SetState(SpawnState);
		if (h.phase == 1 && !h.BossDown())
		{
			fireAcc += h.rate * 0.5 / 35.0;
			if (fireAcc >= 1)
			{
				fireAcc -= 1;
				h.FireBullet(self);
			}
		}
	}
}

// marine waiting on top of a barrel; shoot the barrel, then pick him up
class RRecruit : Actor
{
	RBarrel host;
	bool free;

	Default
	{
		Radius 14;
		Height 50;
		-SOLID
		+NOGRAVITY
		+NOBLOCKMAP
		Translation "112:127=[110,170,255]:[0,25,110]";
	}

	States
	{
	Spawn:
		PLAY A -1;
		stop;
	Wave:
		PLAY E 8;
		PLAY A 8;
		loop;
	}

	void Drop()
	{
		free = true;
		host = null;
		bNOGRAVITY = false;
		SetStateLabel("Wave");
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		Angle = 270;
		if (!free)
		{
			if (host && !host.dead) SetOrigin(host.pos + (0, 0, 32), true);
			else Drop();
			return;
		}
		let h = RunnerHandler.Get();
		if (!h || h.phase != 1) return;
		if (h.defense) SetOrigin(pos - (0, h.approachSpeed, 0), true);
		let pm = players[consoleplayer].mo;
		bool got = pm && abs(pm.pos.x - pos.x) < 32 && abs(pm.pos.y - pos.y) < 32;
		for (int i = 0; !got && i < h.allies.Size(); i++)
		{
			let a = h.allies[i];
			if (a && abs(a.pos.x - pos.x) < 26 && abs(a.pos.y - pos.y) < 26) got = true;
		}
		if (got)
		{
			h.AddAllies(1, pos);
			h.AddFT(StringTable.Localize("$RR_PLUSMARINE"), pos + (0, 0, 60), Font.CR_LIGHTBLUE);
			if (pm) pm.A_StartSound("misc/p_pkup", CHAN_ITEM, 0, RR_VOL);
			Destroy();
		}
		else if (pm && pos.y < pm.pos.y - 260) Destroy();
	}
}

class RTorch : Actor
{
	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
	}

	States
	{
	Spawn:
		TRED ABCD 4 Bright;
		loop;
	Base:
		TLP2 ABCD 4 Bright;
		loop;
	City:
		COLU A -1 Bright;
		stop;
	}

	void SetTheme(int th)
	{
		if (th == 0) SetStateLabel("Base");
		else if (th == 1) SetStateLabel("City");
	}
}

// loot from crates: weapons (1-6), medikit (7), souls (8)
class RPickup : Actor
{
	int kind;

	Default
	{
		+NOGRAVITY
		+FLOATBOB
		+NOBLOCKMAP
		-SOLID
	}

	States
	{
	Spawn:
		TNT1 A -1;
		stop;
	W1:
		SHOT A -1 Bright;
		stop;
	W2:
		SGN2 A -1 Bright;
		stop;
	W3:
		MGUN A -1 Bright;
		stop;
	W4:
		LAUN A -1 Bright;
		stop;
	W5:
		PLAS A -1 Bright;
		stop;
	W6:
		BFUG A -1 Bright;
		stop;
	Medi:
		MEDI A -1 Bright;
		stop;
	Souls:
		SOUL ABCDCB 6 Bright;
		loop;
	}

	void SetKind(int k)
	{
		kind = k;
		switch (k)
		{
		case 1: SetStateLabel("W1"); break;
		case 2: SetStateLabel("W2"); break;
		case 3: SetStateLabel("W3"); break;
		case 4: SetStateLabel("W4"); break;
		case 5: SetStateLabel("W5"); break;
		case 6: SetStateLabel("W6"); break;
		case 7: SetStateLabel("Medi"); break;
		default: SetStateLabel("Souls"); break;
		}
	}

	clearscope String LabelText()
	{
		int k = clamp(kind, 1, 8);
		return StringTable.Localize(k <= 6 ? String.Format("$RR_W%d", k) : String.Format("$RR_P%d", k));
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		let h = RunnerHandler.Get();
		if (!h || h.phase != 1) return;
		if (h.defense) SetOrigin(pos - (0, h.approachSpeed, 0), true);
		let pm = players[consoleplayer].mo;
		if (pm && abs(pm.pos.x - pos.x) < 34 && abs(pm.pos.y - pos.y) < 34)
		{
			h.CollectPickup(self);
			Destroy();
		}
		else if (pm && pos.y < pm.pos.y - 260) Destroy();
	}
}

class RChunk : Actor
{
	Default
	{
		Radius 2;
		Height 2;
		Gravity 0.8;
		-SOLID
		+NOBLOCKMAP
		+NOTELEPORT
		+DROPOFF
	}

	States
	{
	Spawn:
		RCHK A 0 NoDelay A_Jump(128, "Other");
		RCHK A 30;
		RCHK A 1 A_FadeOut(0.06);
		wait;
	Other:
		RCHK B 30;
		RCHK B 1 A_FadeOut(0.06);
		wait;
	}
}

class RFinish : Actor
{
	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
		Scale 1.3;
	}

	States
	{
	Spawn:
		RFIN A -1;
		stop;
	}
}
