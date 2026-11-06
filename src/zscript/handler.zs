// Doom Runner - game logic

const RR_LANE = 76;          // lane centre (runway is 304 wide)
const RR_HALF = 136;         // how far the player may steer
const RR_RANGEUNIT = 70.0;   // one point of "range" in map units
const RR_VOL = 0.85;         // global volume factor for our own sound effects

class RunnerHandler : EventHandler
{
	// persistent progress (mirrored in cvars)
	int money, lvlDmg, lvlRate, lvlHp, stage;

	// phases: 0 = upgrade menu, 1 = running, 2 = result screen
	int phase, phaseTime;
	bool lastWon;
	int runCash, lastPayout, lastBonus;

	// stats of the current run
	double dmg, rate, range;
	int hp, maxHp;
	double fireAcc, trackEnd, runSpeed;
	int weapon;            // 0 pistol .. 6 BFG (only for the current run)

	// defense levels: the player stands, waves come towards him
	bool defense;
	double approachSpeed;
	int winDelay;
	int bannerTime;
	String bannerText;

	int hurtFlash, oldButtons, buyFlash, denyFlash, buyWhich;

	RunnerCam cam;
	bool title;            // TITLEMAP: only the title scene runs
	ui double curX, curY;   // mouse cursor in the upgrade / result screens (screen pixels)
	ui bool curInit;
	RBoss boss;
	Array<RunnerTarget> targets;
	Array<RAlly> allies;
	Array<Actor> extras;
	Array<Actor> runSpawned;   // foreign actors (gore, drops) spawned during a run
	Array<Actor> pickupJunk;
	bool bdMode;               // Brutal Doom detected

	// player projectiles (rockets, plasma, BFG) and the damage they carry
	Array<Actor> shotActors;
	Array<double> shotDmg, shotSplash;

	// floating texts
	Array<double> ftX, ftY, ftZ;
	Array<int> ftT, ftCol;
	Array<String> ftS;

	static clearscope RunnerHandler Get()
	{
		return RunnerHandler(EventHandler.Find("RunnerHandler"));
	}

	static clearscope bool IsDefenseStage(int s) { return s % 3 == 2; }

	// scenery follows Doom II: tech base -> city -> hell, 3 stages each, then again
	static clearscope int ThemeOf(int s) { return (s / 3) % 3; }
	static clearscope String ThemeMap(int t)
	{
		static const String m[] = { "MAP01", "MAP02", "MAP03" };
		return m[clamp(t, 0, 2)];
	}
	static clearscope String ThemeName(int t)
	{
		return StringTable.Localize(String.Format("$RR_THEME%d", clamp(t, 0, 2)));
	}
	String pendingMap;

	int CurrentTheme()
	{
		for (int t = 0; t < 3; t++) if (level.MapName ~== ThemeMap(t)) return t;
		return 0;
	}

	// kill combo
	int comboCount, comboTimer, comboShow;
	void AddKill(Vector3 p)
	{
		if (phase != 1) return;
		comboCount++;
		comboTimer = 45;
		comboShow = 35;
		if (comboCount >= 5 && comboCount % 5 == 0)
		{
			int bonus = comboCount;
			runCash += bonus;
			AddFT(String.Format(StringTable.Localize("$RR_COMBO"), comboCount, bonus), p + (0, 0, 30), Font.CR_GOLD);
			let pm = players[consoleplayer].mo;
			if (pm) pm.A_StartSound("misc/p_pkup", CHAN_AUTO, 0, RR_VOL);
		}
	}

	// ------------------------------------------------------------ upgrades
	clearscope double UpVal(int which, int l)
	{
		if (which == 0) return 1.0 + 0.115 * l;
		if (which == 1) return 2.0 + 0.12 * l;
		return 10 + 2 * l;
	}

	clearscope int UpCost(int which, int l)
	{
		double b = which == 0 ? 20 : (which == 1 ? 16 : 12);
		return int(b * (1.0 + 0.35 * l) + 2 * l * l);
	}

	clearscope int UpLevel(int which)
	{
		if (which == 0) return lvlDmg;
		if (which == 1) return lvlRate;
		return lvlHp;
	}

	void LoadProgress()
	{
		money   = CVar.FindCVar('rr_money').GetInt();
		lvlDmg  = CVar.FindCVar('rr_lvl_dmg').GetInt();
		lvlRate = CVar.FindCVar('rr_lvl_rate').GetInt();
		lvlHp   = CVar.FindCVar('rr_lvl_hp').GetInt();
		stage   = CVar.FindCVar('rr_stage').GetInt();
	}

	void SaveProgress()
	{
		CVar.FindCVar('rr_money').SetInt(money);
		CVar.FindCVar('rr_lvl_dmg').SetInt(lvlDmg);
		CVar.FindCVar('rr_lvl_rate').SetInt(lvlRate);
		CVar.FindCVar('rr_lvl_hp').SetInt(lvlHp);
		CVar.FindCVar('rr_stage').SetInt(stage);
	}

	void Buy(int which)
	{
		if (phase != 0 || which < 0 || which > 2) return;
		let pm = players[consoleplayer].mo;
		int c = UpCost(which, UpLevel(which));
		buyWhich = which;
		if (money < c)
		{
			denyFlash = 14;
			if (pm) pm.A_StartSound("*usefail", CHAN_VOICE, 0, RR_VOL);
			return;
		}
		money -= c;
		if (which == 0) lvlDmg++;
		else if (which == 1) lvlRate++;
		else lvlHp++;
		buyFlash = 14;
		SaveProgress();
		if (pm) pm.A_StartSound("misc/w_pkup", CHAN_ITEM, 0, RR_VOL);
	}

	// -------------------------------------------------------------- events
	static bool ClassExists(String n)
	{
		class<Actor> c = n;
		return c != null;
	}

	static bool DetectBrutalDoom()
	{
		return ClassExists("RifleZombie") || ClassExists("Doomer") || ClassExists("ShotgunGuy1");
	}

	override void WorldLoaded(WorldEvent e)
	{
		bdMode = DetectBrutalDoom();
		ApplyGore(consoleplayer);
		if (bdMode)
		{
			// no Brutal Doom tips / welcome text at the top of the screen
			let tips = CVar.GetCVar('bd_Tips', players[consoleplayer]);
			if (tips && tips.GetInt() != 0) tips.SetInt(0);
			let welcome = CVar.FindCVar('BD_Welcome');
			if (welcome && welcome.GetInt() != 0) welcome.SetInt(0);
		}
		if (level.MapName ~== "TITLEMAP")
		{
			title = true;
			BuildTitle();
			return;
		}
		if (e.IsSaveGame) return;
		LoadProgress();
		int th = CurrentTheme();
		double stepY = th == 1 ? 384 : (th == 0 ? 256 : 280);
		double xs = th == 1 ? 168 : 162;
		for (double ty = -1000; ty < 24500; ty += stepY)
		{
			let t1 = RTorch(Actor.Spawn("RTorch", (-xs, ty, 0)));
			let t2 = RTorch(Actor.Spawn("RTorch", (xs, ty, 0)));
			if (t1) t1.SetTheme(th);
			if (t2) t2.SetTheme(th);
		}
		let pm = players[consoleplayer].mo;
		if (pm)
		{
			cam = RunnerCam(Actor.Spawn("RunnerCam", pm.pos));
			cam.target = pm;
		}
		EnterMenu();
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		let mo = e.Thing;
		if (!mo || phase != 1) return;
		if (mo is "RunnerTarget" || mo is "RBullet" || mo is "REBullet" || mo is "RAlly" || mo is "RPickup"
			|| mo is "RChunk" || mo is "RRecruit" || mo is "RunnerCam" || mo is "PlayerPawn" || mo is "RTorch") return;
		let inv = Inventory(mo);
		if (inv)
		{
			if (!inv.Owner) pickupJunk.Push(mo);   // monster drops: remove next tic
			return;
		}
		if (runSpawned.Size() < 8000) runSpawned.Push(mo);
	}

	// play a real (possibly Brutal Doom replaced) death of a Doom actor at pos
	Actor SpawnDeath(Name cls, Vector3 pos, double ang, bool extreme)
	{
		class<Actor> c = cls;
		if (!c) return null;
		let mo = Actor.Spawn(c, pos, ALLOW_REPLACE);
		if (!mo) return null;
		mo.Angle = ang;
		mo.bSOLID = false;
		mo.bFRIENDLY = true;
		let pm = players[consoleplayer].mo;
		int d = extreme ? mo.Health * 10 + 100 : mo.Health;
		mo.DamageMobj(pm, pm, d, extreme ? 'Extreme' : 'None', DMG_FORCED | DMG_THRUSTLESS);
		mo.bSOLID = false;
		return mo;
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (title && !(e.Name ~== "rr_reset") && !(e.Name ~== "rr_goreapply")) return;
		if (e.Name ~== "rr_buy") Buy(e.Args[0]);
		else if (e.Name ~== "rr_play")
		{
			if (phase == 0) StartRun();
			else if (phase == 2 && phaseTime > 20) EnterMenu();
		}
		else if (e.Name ~== "rr_cheatcash")
		{
			money += 1000;
			SaveProgress();
		}
		else if (e.Name ~== "rr_goreapply")
		{
			ApplyGore(e.Player);
		}
		else if (e.Name ~== "rr_reset")
		{
			money = 0; lvlDmg = 0; lvlRate = 0; lvlHp = 0; stage = 0;
			SaveProgress();
			if (!title) EnterMenu();
		}
	}

	// gore option: Brutal Doom blood amount, then let BD re-read its settings
	// (the gib limit is an engine cvar and is set by the menu item)
	void ApplyGore(int pnum)
	{
		if (!bdMode) return;
		static const int blood[] = { 2, 3, 4, 666 };
		let gc = CVar.GetCVar('rr_gore', players[pnum]);
		int g = gc ? clamp(gc.GetInt(), 0, 3) : 0;
		let c = CVar.FindCVar('zdoombrutalblood');
		if (c) c.SetInt(blood[g]);
		goreRefresh = 3;   // server cvar changes land a tic later
	}
	int goreRefresh;

	override bool InputProcess(InputEvent e)
	{
		if (title) return false;
		// mouse: moves our cursor outside of runs (during a run it steers via the normal turn input)
		if (e.Type == InputEvent.Type_Mouse)
		{
			if (phase == 1) return false;
			MoveCursor(e.MouseX, e.MouseY);
			return true;
		}
		if (e.Type != InputEvent.Type_KeyDown) return false;
		int k = e.KeyScan;
		if (k == InputEvent.Key_Mouse1 && phase != 1)
		{
			if (phase == 0)
			{
				int hit = MenuHit(curX, curY);
				if (hit >= 0 && hit < 3) SendNetworkEvent("rr_buy", hit);
				else if (hit == 3) SendNetworkEvent("rr_play");
			}
			else SendNetworkEvent("rr_play");
			return true;
		}
		bool confirm = (k == 57 || k == 28 || k == 156); // space / enter / keypad enter
		if (phase == 0)
		{
			if (k == 2 || k == 79) { SendNetworkEvent("rr_buy", 0); return true; }
			if (k == 3 || k == 80) { SendNetworkEvent("rr_buy", 1); return true; }
			if (k == 4 || k == 81) { SendNetworkEvent("rr_buy", 2); return true; }
			if (confirm) { SendNetworkEvent("rr_play"); return true; }
		}
		else if (phase == 2 && confirm)
		{
			SendNetworkEvent("rr_play");
			return true;
		}
		return false;
	}

	override void WorldTick()
	{
		if (goreRefresh > 0 && --goreRefresh == 0)
		{
			let gp = players[consoleplayer].mo;
			if (gp) gp.ACS_NamedExecuteAlways("GetCVars", 0);
		}
		if (title) { TitleTick(); return; }
		let pm = players[consoleplayer].mo;
		if (!pm) return;
		if (!cam)
		{
			cam = RunnerCam(Actor.Spawn("RunnerCam", pm.pos));
			cam.target = pm;
			SetupCamera();
		}
		players[consoleplayer].camera = cam;

		if (pendingMap != "")
		{
			String m = pendingMap;
			pendingMap = "";
			level.ChangeLevel(m, 0, CHANGELEVEL_NOINTERMISSION);
			return;
		}

		phaseTime++;
		if (hurtFlash > 0) hurtFlash--;
		if (buyFlash > 0) buyFlash--;
		if (denyFlash > 0) denyFlash--;
		if (bannerTime > 0) bannerTime--;
		if (comboShow > 0) comboShow--;
		if (comboTimer > 0 && --comboTimer == 0) comboCount = 0;
		for (int i = 0; i < pickupJunk.Size(); i++)
		{
			let inv = Inventory(pickupJunk[i]);
			if (inv && !inv.Owner) inv.Destroy();
		}
		pickupJunk.Clear();
		for (int i = shotActors.Size() - 1; i >= 0; i--)
		{
			if (!shotActors[i]) { shotActors.Delete(i); shotDmg.Delete(i); shotSplash.Delete(i); }
		}

		for (int i = ftT.Size() - 1; i >= 0; i--)
		{
			ftT[i]--;
			ftZ[i] += 1.1;
			if (ftT[i] <= 0) RemoveFT(i);
		}

		int btn = players[consoleplayer].cmd.buttons;
		bool fire = (btn & BT_ATTACK) && !(oldButtons & BT_ATTACK);
		oldButtons = btn;

		if (phase == 0)
		{
			int at = CVar.FindCVar('rr_autotest').GetInt();
			if (fire && phaseTime > 10) StartRun();
			else if (at > 0 && phaseTime == at * 35) StartRun();
		}
		else if (phase == 2)
		{
			if (fire && phaseTime > 30) EnterMenu();
		}
		else RunTick(pm);
	}

	// --------------------------------------------------------------- flow
	void SetupCamera()
	{
		if (!cam) return;
		bool indoor = CurrentTheme() == 0;
		if (defense) cam.SetView(210, indoor ? 230 : 250, 38);
		else cam.SetView(190, 150, 22);
		cam.Snap();
	}

	void EnterMenu()
	{
		int want = ThemeOf(stage);
		if (!(level.MapName ~== ThemeMap(want)))
		{
			// switch scenery on the next tic (not allowed while the level is loading)
			phase = 0;
			pendingMap = ThemeMap(want);
			return;
		}
		ClearTrack();
		let pm = players[consoleplayer].mo;
		if (pm)
		{
			pm.SetOrigin((0, 0, 0), false);
			pm.Vel = (0, 0, 0);
			pm.ClearInterpolation();
			pm.SetState(pm.SpawnState);
		}
		phase = 0;
		phaseTime = 0;
		runSpeed = 0;
		defense = IsDefenseStage(stage);
		if (defense) BuildDefense();
		else BuildTrack();
		SetupCamera();
	}

	void StartRun()
	{
		dmg = UpVal(0, lvlDmg);
		rate = UpVal(1, lvlRate);
		maxHp = int(UpVal(2, lvlHp));
		hp = maxHp;
		range = 8.0;
		runCash = 0;
		fireAcc = 0.9;
		weapon = 0;
		winDelay = 0;
		bannerTime = 0;
		comboCount = 0;
		comboTimer = 0;
		phase = 1;
		phaseTime = 0;
		if (defense) ShowBanner(StringTable.Localize("$RR_DEFEND"));
	}

	void ShowBanner(String s)
	{
		if (s == "") return;
		bannerText = s;
		bannerTime = 70;
		let pm = players[consoleplayer].mo;
		if (pm) pm.A_StartSound("misc/chat", CHAN_AUTO, 0, RR_VOL);
	}

	// boss dead (or already removed after a Brutal Doom death)
	clearscope bool BossDown() { return !boss || boss.dead; }

	void RunTick(Actor pm)
	{
		if (defense)
		{
			runSpeed = 0;
			approachSpeed = 2.0 + min(stage, 12) * 0.05;
		}
		else
		{
			runSpeed = 3.0 + min(stage, 8) * 0.08;
			if (boss && !boss.dead && pm.pos.y > boss.pos.y - 300) runSpeed = 0;
		}

		if (BossDown()) fireAcc = 0;
		else fireAcc += rate * WRate(weapon) / 35.0;
		while (fireAcc >= 1.0)
		{
			fireAcc -= 1.0;
			FirePlayer(pm);
		}

		if (defense)
		{
			if (!boss || boss.dead)
			{
				if (++winDelay > 70) EndRun(true);
			}
		}
		else if (pm.pos.y >= trackEnd) EndRun(true);
	}

	// ------------------------------------------------------------ weapons
	clearscope String WName(int w)
	{
		return StringTable.Localize(String.Format("$RR_W%d", clamp(w, 0, 6)));
	}
	clearscope String WIcon(int w)
	{
		static const String n[] = { "PISTA0", "SHOTA0", "SGN2A0", "MGUNA0", "LAUNA0", "PLASA0", "BFUGA0" };
		return n[clamp(w, 0, 6)];
	}
	clearscope double WRate(int w)
	{
		static const double v[] = { 1.0, 0.75, 0.5, 2.0, 0.55, 2.2, 0.25 };
		return v[clamp(w, 0, 6)];
	}
	clearscope double WDmg(int w)
	{
		static const double v[] = { 1.0, 0.8, 0.85, 0.7, 2.5, 0.9, 6.0 };
		return v[clamp(w, 0, 6)];
	}

	String FireSound(int w)
	{
		static const String doomSnd[] = { "weapons/pistol", "weapons/shotgf", "weapons/sshotf", "weapons/chngun", "weapons/rocklf", "weapons/plasmaf", "weapons/bfgf" };
		static const String bdSnd[] = { "Pistol/Fire", "Shotgun/Fire", "SSG/Fire", "Chaingun/Fire", "Rocket/Fire", "Plasma/Fire", "BFG/Fire" };
		w = clamp(w, 0, 6);
		return bdMode ? bdSnd[w] : doomSnd[w];
	}

	void FirePlayer(Actor pm)
	{
		static const int pellets[] = { 1, 3, 7, 1, 1, 1, 1 };
		static const double spread[] = { 0, 5, 10, 2, 0, 0, 0 };
		static const String proj[] = { "", "", "", "", "Rocket", "PlasmaBall", "BFGBall" };
		static const double splashK[] = { 0, 0, 0, 0, 0.6, 0, 0.5 };
		int w = clamp(weapon, 0, 6);
		double d = dmg * WDmg(w);
		if (w <= 3)
		{
			int n = pellets[w];
			for (int i = 0; i < n; i++)
			{
				double ofs = n > 1 ? -spread[w] + 2 * spread[w] * i / (n - 1.0) + FRandom(-1, 1) : FRandom(-spread[w], spread[w]);
				FireHitscan(pm, 90 + ofs, d, i == 0 || i == n - 1);
			}
			SpawnCasing(pm, w);
		}
		else FireProjectile(pm, proj[w], d, d * splashK[w]);
		pm.A_StartSound(FireSound(w), CHAN_WEAPON, CHANF_OVERLAP, (w == 0 ? 0.35 : 0.5) * RR_VOL);
	}

	// real hitscan with the game's own bullet puff (Brutal Doom: its HitPuff)
	void FireHitscan(Actor shooter, double ang, double d, bool fx)
	{
		FTranslatedLineTarget lt;
		shooter.LineAttack(ang, range * RR_RANGEUNIT, 0, max(1, int(d * 10 + 0.5)), 'RunnerShot', "BulletPuff", 0, lt, -20);
		if (!fx) return;
		Vector3 from = shooter.pos + (cos(ang) * 14, sin(ang) * 14, 16);
		Actor tr = null;
		if (bdMode)
		{
			String tn = "DecorativeTracer";   // Brutal Doom class, looked up at runtime
			class<Actor> tc = tn;
			if (tc) tr = Actor.Spawn(tc, from);
		}
		if (!tr)
		{
			let t2 = RTracerFX(Actor.Spawn("RTracerFX", from));
			if (t2) t2.life = int(range * RR_RANGEUNIT / 40);
			tr = t2;
		}
		if (tr)
		{
			tr.target = shooter;
			tr.Angle = ang;
			tr.Vel = (cos(ang) * 40, sin(ang) * 40, 0);
		}
	}

	// real Doom projectiles (replaced by Brutal Doom's versions when loaded)
	void FireProjectile(Actor shooter, String clsName, double d, double splash)
	{
		class<Actor> c = clsName;
		if (!c) return;
		let mo = Actor.Spawn(c, shooter.pos + (0, 18, 22), ALLOW_REPLACE);
		if (!mo) return;
		mo.target = shooter;
		mo.Angle = 90;
		double sp = mo.Speed > 0 ? mo.Speed : 20;
		mo.Vel = (0, sp, 0);
		shotActors.Push(mo);
		shotDmg.Push(d);
		shotSplash.Push(splash);
	}

	// Brutal Doom shell casings flying out of the gun
	void SpawnCasing(Actor pm, int w)
	{
		if (!bdMode) return;
		static const String cases[] = { "PistolCaseSpawn", "ShotCaseSpawn", "ShotCaseSpawn", "50CaseSpawn2" };
		class<Actor> c = cases[clamp(w, 0, 3)];
		if (c) pm.A_SpawnItemEx(c, 4, -6, 26, 0, 0, 0, 0, SXF_NOCHECKPOSITION);
	}

	// how much of an incoming hit counts as our damage
	double ResolveDamage(Actor inflictor, Actor source, int damage, Name mod, int flags)
	{
		if (mod == 'RunnerShot') return damage / 10.0;
		if (inflictor)
		{
			int i = shotActors.Find(inflictor);
			if (i < shotActors.Size()) return (flags & DMG_EXPLOSION) ? shotSplash[i] : shotDmg[i];
		}
		return 0;
	}

	// area damage to everything shootable on the track (not gates)
	void Splash(Vector3 p, double r, double d, Actor skip)
	{
		for (int i = 0; i < targets.Size(); i++)
		{
			let t = targets[i];
			if (!t || t == skip || t.dead || t is "RGate") continue;
			double dist = (t.pos.xy - p.xy).Length() - t.radius;
			if (dist > r) continue;
			t.OnShot(d * (dist <= 0 ? 1.0 : 1.0 - 0.5 * dist / r), null);
		}
	}

	void SetWeapon(int w, Vector3 p)
	{
		weapon = clamp(w, 0, 6);
		AddFT(WName(weapon), p, Font.CR_GOLD);
		let pm = players[consoleplayer].mo;
		if (pm) pm.A_StartSound("misc/w_pkup", CHAN_ITEM, 0, RR_VOL);
	}

	// crate loot: weapons get better with the stage
	void RollDrop(Vector3 p)
	{
		int kind;
		int r = Random(0, 99);
		if (r < (defense ? 65 : 50))
		{
			Array<int> pool;
			pool.Push(1); pool.Push(1); pool.Push(3); pool.Push(3);
			if (stage >= 3) { pool.Push(2); pool.Push(3); }
			if (stage >= 4) { pool.Push(5); pool.Push(2); }
			if (stage >= 6 && Random(0, 99) < 25) pool.Push(6);
			kind = pool[Random(0, pool.Size() - 1)];
		}
		else if (r < 80) kind = 8;
		else kind = 7;
		int forced = CVar.FindCVar('rr_autotest').GetInt() > 0 ? CVar.FindCVar('rr_testdrop').GetInt() : 0;
		if (forced > 0) kind = forced;   // test hook
		let pk = RPickup(Actor.Spawn("RPickup", (p.x, p.y, 20)));
		if (pk)
		{
			pk.SetKind(kind);
			extras.Push(pk);
		}
	}

	void CollectPickup(RPickup pk)
	{
		let pm = players[consoleplayer].mo;
		Vector3 at = pm ? pm.pos + (0, 110, 64) : pk.pos;
		if (pk.kind >= 1 && pk.kind <= 6) SetWeapon(pk.kind, at);
		else if (pk.kind == 7)
		{
			hp = min(hp + 3, 99);
			maxHp = max(maxHp, hp);
			AddFT(StringTable.Localize("$RR_HP3"), at, Font.CR_GREEN);
			if (pm) pm.A_StartSound("misc/i_pkup", CHAN_ITEM, 0, RR_VOL);
		}
		else
		{
			AddCash(10 + stage * 5, at);
			if (pm) pm.A_StartSound("misc/p_pkup", CHAN_ITEM, 0, RR_VOL);
		}
	}

	void EndRun(bool won)
	{
		if (phase != 1) return;
		phase = 2;
		phaseTime = 0;
		lastWon = won;
		lastBonus = won ? 15 + stage * 10 : 0;
		lastPayout = runCash + lastBonus;
		money += lastPayout;
		if (won) stage++;
		SaveProgress();
		runSpeed = 0;
		let pm = players[consoleplayer].mo;
		if (pm)
		{
			if (won) pm.A_StartSound("misc/secret", CHAN_AUTO, 0, RR_VOL);
			else
			{
				pm.SetStateLabel("Fallen");
				pm.A_StartSound("*death", CHAN_VOICE, 0, RR_VOL);
			}
		}
	}

	void DamagePlayer(int n)
	{
		if (phase != 1) return;
		hp -= n;
		hurtFlash = 12;
		let pm = players[consoleplayer].mo;
		if (hp <= 0)
		{
			hp = 0;
			EndRun(false);
		}
		else if (pm) pm.A_StartSound("*pain100", CHAN_VOICE, 0, RR_VOL);
	}

	// allies: simple bullets that can never hit the player. They aim at the
	// player's line of fire (40 % of the way), so the squad focuses its fire.
	void FireBullet(Actor shooter)
	{
		let pm = players[consoleplayer].mo;
		let b = RBullet(Actor.Spawn("RBullet", shooter.pos + (0, 14, 16)));
		if (!b) return;
		b.target = shooter;
		b.dmg = dmg;
		b.maxDist = range * RR_RANGEUNIT;
		b.startY = shooter.pos.y;
		double dx = pm ? (pm.pos.x - shooter.pos.x) * 0.4 : 0;
		double a = atan2(450, dx);
		b.Angle = a;
		b.Vel = (cos(a) * b.Speed, sin(a) * b.Speed, 0);
	}

	void ApplyGate(RGate g)
	{
		let pm = players[consoleplayer].mo;
		switch (g.kind)
		{
		case 0: dmg = max(0.2, dmg + g.value); break;
		case 1: rate = max(0.5, rate + g.value); break;
		case 2: range = max(2.5, range + g.value); break;
		case 3:
		{
			int n = g.IntVal();
			if (n > 0) AddAllies(n, pm.pos + (0, 16, 0));
			else RemoveAllies(-n);
			break;
		}
		default:
		{
			int n = g.IntVal();
			hp = min(hp + n, 99);
			maxHp = max(maxHp, hp);
			if (hp <= 0) { hp = 0; EndRun(false); }
			break;
		}
		}
		bool good = g.value >= 0;
		AddFT(g.KindName() .. " " .. g.ValueText(), pm.pos + (0, 110, 64), good ? Font.CR_GREEN : Font.CR_RED);
		pm.A_StartSound(good ? "misc/p_pkup" : "misc/i_pkup", CHAN_ITEM, 0, RR_VOL);
		if (!good) hurtFlash = 6;
	}

	void AddAllies(int n, Vector3 from)
	{
		for (int i = 0; i < n; i++)
		{
			if (allies.Size() >= 30) break;
			let a = RAlly(Actor.Spawn("RAlly", from + (FRandom(-14, 14), FRandom(-14, 14), 0)));
			if (a) allies.Push(a);
		}
	}

	void RemoveAllies(int n)
	{
		while (n > 0 && allies.Size() > 0)
		{
			let a = allies[allies.Size() - 1];
			if (a) a.AllyDie();
			else allies.Pop();
			n--;
		}
	}

	void AllyDied(RAlly a)
	{
		int i = allies.Find(a);
		if (i < allies.Size()) allies.Delete(i);
	}

	// tight squad formation around the player
	static clearscope Vector2 SlotOffset(int i)
	{
		static const double xs[] = { -30, 30, -60, 60, 0 };
		int row = i / 5;
		int col = i % 5;
		double xo = xs[col] + ((row % 2) ? 15 : 0);
		double yo = -26 - row * 30 - (col == 4 ? 18 : 0);
		return (xo, yo);
	}

	void AddFT(String s, Vector3 p, int col)
	{
		ftS.Push(s); ftX.Push(p.x); ftY.Push(p.y); ftZ.Push(p.z); ftT.Push(50); ftCol.Push(col);
	}

	void RemoveFT(int i)
	{
		ftS.Delete(i); ftX.Delete(i); ftY.Delete(i); ftZ.Delete(i); ftT.Delete(i); ftCol.Delete(i);
	}

	void AddCash(int n, Vector3 p)
	{
		if (phase != 1) return;
		runCash += n;
		AddFT(String.Format("+%d", n), p, Font.CR_GREEN);
	}

	// -------------------------------------------------------------- track
	void ClearTrack()
	{
		for (int i = 0; i < targets.Size(); i++) if (targets[i]) targets[i].Destroy();
		for (int i = 0; i < allies.Size(); i++) if (allies[i]) allies[i].Destroy();
		for (int i = 0; i < extras.Size(); i++) if (extras[i]) extras[i].Destroy();
		targets.Clear();
		allies.Clear();
		extras.Clear();
		for (int i = 0; i < runSpawned.Size(); i++)
		{
			let mo = runSpawned[i];
			if (!mo || mo.player) continue;
			let inv = Inventory(mo);
			if (inv && inv.Owner) continue;
			mo.Destroy();
		}
		runSpawned.Clear();
		shotActors.Clear(); shotDmg.Clear(); shotSplash.Clear();
		boss = null;
		ftS.Clear(); ftX.Clear(); ftY.Clear(); ftZ.Clear(); ftT.Clear(); ftCol.Clear();

		Array<Actor> junk;
		let it = ThinkerIterator.Create("Actor");
		Actor mo;
		while ((mo = Actor(it.Next())) != null)
		{
			if (mo is "RBullet" || mo is "REBullet" || mo is "RTracerFX" || mo is "RChunk" || mo is "RPickup"
				|| mo is "RAlly" || mo is "RRecruit" || mo is "RunnerTarget" || mo is "RFinish")
				junk.Push(mo);
		}
		for (int i = 0; i < junk.Size(); i++) junk[i].Destroy();
	}

	RunnerTarget SpawnT(class<RunnerTarget> cls, double x, double y)
	{
		let t = RunnerTarget(Actor.Spawn(cls, (x, y, 0)));
		targets.Push(t);
		return t;
	}

	void TestCrate()
	{
		if (CVar.FindCVar('rr_testdrop').GetInt() > 0)
		{
			let tc = RCrate(SpawnT("RCrate", 0, 380));   // test hook
			tc.hp = 1; tc.maxhp = 1;
		}
	}

	// row types: 0 gate pair, 1 gate + barrel, 2 barrels, 3 enemies, 4 crates
	void BuildTrack()
	{
		trackEnd = min(3400 + stage * 380, 12000);
		int rows = max(5, int((trackEnd - 1300) / 470));
		Array<int> plan;
		int nEnemy = max(2, int(rows * 0.32 + 0.5));
		int nCrate = stage >= 2 ? max(1, int(rows * (0.12 + min(stage, 8) * 0.012) + 0.5)) : 0;
		int nGate = max(2, int(rows * 0.28 + 0.5));
		for (int i = 0; i < nEnemy; i++) plan.Push(3);
		for (int i = 0; i < nCrate; i++) plan.Push(4);
		for (int i = 0; i < nGate; i++) plan.Push(0);
		while (plan.Size() < rows) plan.Push(plan.Size() % 2 ? 1 : 2);
		for (int i = plan.Size() - 1; i > 0; i--)
		{
			int j = Random(0, i);
			int tmp = plan[i]; plan[i] = plan[j]; plan[j] = tmp;
		}
		// always open with a gate pair, never two enemy rows at the very start
		for (int i = 0; i < plan.Size(); i++)
		{
			if (plan[i] == 0) { int tmp = plan[0]; plan[0] = 0; plan[i] = tmp; break; }
		}
		if (plan.Size() > 2 && plan[1] == 3 && plan[2] != 3) { plan[1] = plan[2]; plan[2] = 3; }

		TestCrate();
		firstEnemyRow = true;
		lastGroupType = -1;
		double y = 650;
		for (int i = 0; i < plan.Size() && y < trackEnd - 650; i++)
		{
			double prog = y / trackEnd;
			switch (plan[i])
			{
			case 0: RowGatePair(y); break;
			case 1: RowGateBarrel(y, prog); break;
			case 2: RowBarrels(y, prog); break;
			case 3: RowEnemies(y, prog); break;
			default: RowCrates(y, prog); break;
			}
			y += FRandom(430, 540);
		}
		boss = SpawnBoss(0, trackEnd - 300);
		boss.hp = int((50 + stage * 30) * (1 + stage * 0.06));
		boss.maxhp = boss.hp;
		boss.leader = true;
		extras.Push(Actor.Spawn("RFinish", (0, trackEnd, 0)));
	}

	// defense: supplies (gates, crates) and then a zombie horde, several waves, then the boss
	void BuildDefense()
	{
		trackEnd = 0;
		lastGroupType = -1;
		TestCrate();
		int waves = 5 + min(stage / 3, 4);
		double y = 700;
		for (int w = 0; w < waves; w++)
		{
			double prog = double(w) / waves;
			RowGatePair(y);
			y += 330;
			if (w % 2 == 0) RowCrates(y, prog);
			else RowGateBarrel(y, prog);
			y += 380;
			y = RowHorde(y, prog, w);
			y += 420;
		}
		boss = SpawnBoss(0, y + 200);
		boss.hp = int((90 + stage * 45) * (1 + stage * 0.06));
		boss.maxhp = boss.hp;
		boss.leader = true;
	}

	// ---------------------------------------------------- bosses
	// running levels: Hell Knight / Baron / Cyberdemon;
	// episode finales (defense): Mancubus / Spider Mastermind / Cyberdemon
	RBoss SpawnBoss(double x, double y)
	{
		static const String runBoss[] = { "RBossKnight", "RBossBaron", "RBossCyber" };
		static const String finBoss[] = { "RBossFatso", "RBossSpider", "RBossCyber" };
		int th = ThemeOf(stage);
		class<RunnerTarget> c = defense ? finBoss[th] : runBoss[th];
		return RBoss(SpawnT(c, x, y));
	}

	// ---------------------------------------------------- enemy groups
	// every group is one kind of monster ("sortenrein"). Types:
	// 0 zombie, 1 sergeant, 2 imp, 3 demon (pinky), 4 lost soul
	int lastGroupType;

	int PickGroupType(bool firstOfLevel)
	{
		int th = ThemeOf(stage);
		int sub = stage % 3;
		bool again = stage >= 9;
		if (firstOfLevel) return th == 2 ? 2 : 0;
		Array<int> pool;
		if (th == 0)
		{
			pool.Push(0);
			if (sub >= 1 || again) pool.Push(1);
			if (sub >= 2 || again) pool.Push(2);
		}
		else if (th == 1)
		{
			pool.Push(0); pool.Push(1); pool.Push(2); pool.Push(3);
			if (sub >= 1 || again) pool.Push(4);
		}
		else
		{
			pool.Push(2); pool.Push(3); pool.Push(4); pool.Push(1);
		}
		int t = pool[Random(0, pool.Size() - 1)];
		if (t == lastGroupType && pool.Size() > 1) t = pool[Random(0, pool.Size() - 1)];
		lastGroupType = t;
		return t;
	}

	REnemy SpawnGroupMember(int type, double x, double y, double hpv)
	{
		static const String cls[] = { "REnemy", "RSergeant", "RImp", "RDemon", "RLostSoul" };
		static const double hpMul[] = { 1.0, 1.5, 1.3, 2.2, 0.6 };
		type = clamp(type, 0, 4);
		class<RunnerTarget> c = cls[type];
		let en = REnemy(SpawnT(c, x, y));
		en.hp = max(1, int(hpv * hpMul[type] * FRandom(0.85, 1.15) + 0.5));
		en.maxhp = en.hp;
		return en;
	}

	double RowHorde(double y, double prog, int wave)
	{
		static const double countMul[] = { 1.0, 0.7, 0.6, 0.5, 0.9 };
		static const double headStart[] = { 0, 0, 250, 450, 650 };   // fast kinds start further away
		int type = PickGroupType(wave == 0);
		y += headStart[type];
		int n = max(4, int(min(8 + stage * 2 + wave * 2, 40) * countMul[type]));
		if (defense) n = max(8, int(min(10 + stage * 3 + wave * 5, 75) * countMul[type]));
		double hpv = 1 + stage * 0.45 + prog * 2;
		double depth = 160 + n * 9;
		for (int i = 0; i < n; i++)
		{
			double yy = i == 0 ? y : y + FRandom(0, depth);
			let en = SpawnGroupMember(type, FRandom(-RR_HALF + 6, RR_HALF - 6), yy, hpv);
			en.leader = (i == 0);
		}
		// explosive barrels hidden in the horde: shoot them for chain kills
		int nb = defense ? 2 + Random(0, 2) : 1 + Random(0, 1);
		for (int i = 0; i < nb; i++) MakeBarrel(FRandom(-110, 110), y + FRandom(depth * 0.2, depth * 0.8), prog, false);
		return y + depth;
	}

	void RowCrates(double y, double prog)
	{
		double base = 4 + stage * 1.8 + prog * (4 + stage * 1.2);
		int side = Random(0, 1) ? 1 : -1;
		let c = RCrate(SpawnT("RCrate", side * RR_LANE, y));
		c.hp = max(2, int(base * FRandom(0.9, 1.3) + 0.5));
		c.maxhp = c.hp;
		if (Random(0, 99) < 40)
		{
			let c2 = RCrate(SpawnT("RCrate", -side * RR_LANE, y + FRandom(-30, 30)));
			c2.hp = max(2, int(base * FRandom(0.9, 1.3) + 0.5));
			c2.maxhp = c2.hp;
		}
		else MakeBarrel(-side * RR_LANE, y, prog, true);
	}

	int SetupGate(RGate g, bool good, int avoid)
	{
		int k;
		do { k = Random(0, 4); } while (k == avoid);
		double v;
		switch (k)
		{
		case 0:  v = Random(10, 30) * 0.01; break;
		case 1:  v = Random(2, 6) * 0.1; break;
		case 2:  v = Random(1, 4) * 0.5; break;
		case 3:  v = Random(1, 3) + (defense ? 2 : 0); break;
		default: v = Random(2, 5); break;
		}
		if (!good) v = -v;
		g.kind = k;
		g.value = v;
		return k;
	}

	void RowGatePair(double y)
	{
		bool leftGood = Random(0, 1) == 1;
		bool bothGood = Random(0, 99) < 25;
		let g1 = RGate(SpawnT("RGate", -RR_LANE, y));
		let g2 = RGate(SpawnT("RGate", RR_LANE, y));
		int k = SetupGate(g1, leftGood || bothGood, -1);
		SetupGate(g2, !leftGood || bothGood, k);
	}

	void RowGateBarrel(double y, double prog)
	{
		int side = Random(0, 1) ? 1 : -1;
		let g = RGate(SpawnT("RGate", side * RR_LANE, y));
		SetupGate(g, Random(0, 99) < 65, -1);
		MakeBarrel(-side * RR_LANE, y, prog, true);
		if (Random(0, 1)) MakeBarrel(-side * RR_LANE, y + 70, prog, false);
	}

	void RowBarrels(double y, double prog)
	{
		int n = Random(1, 3);
		if (n == 1) MakeBarrel(RR_LANE * Random(-1, 1), y, prog, true);
		else if (n == 2)
		{
			MakeBarrel(-RR_LANE, y, prog, true);
			MakeBarrel(RR_LANE, y, prog, true);
		}
		else
		{
			MakeBarrel(-100, y, prog, true);
			MakeBarrel(0, y, prog, false);
			MakeBarrel(100, y, prog, true);
		}
	}

	bool firstEnemyRow;

	void RowEnemies(double y, double prog)
	{
		static const double countMul[] = { 1.0, 0.75, 0.6, 0.5, 0.9 };
		int type = PickGroupType(firstEnemyRow);
		firstEnemyRow = false;
		int n = max(2, int((3 + min(stage, 10) * 0.5 + Random(0, 1)) * countMul[type] + 0.5));
		double hpv = 2 + stage * 1.0 + prog * 3;
		// a loose pack: up to 4 side by side, further rows behind
		int perRow = min(n, 4);
		for (int i = 0; i < n; i++)
		{
			int col = i % perRow;
			int row = i / perRow;
			double x = -105 + 210.0 * (col + 0.5) / perRow + FRandom(-10, 10) + (row % 2) * 20;
			let en = SpawnGroupMember(type, clamp(x, -RR_HALF, RR_HALF), y + row * 45 + FRandom(-12, 12), hpv);
			en.leader = (i == 0);
		}
		if (Random(0, 99) < 35) MakeBarrel(FRandom(-90, 90), y + FRandom(10, 60), prog, false);
	}

	void MakeBarrel(double x, double y, double prog, bool allowRider)
	{
		let b = RBarrel(SpawnT("RBarrel", x, y));
		double base = 3 + stage * 1.6 + prog * (4 + stage * 1.2);
		b.hp = max(1, int(base * FRandom(0.6, 1.3) + 0.5));
		b.maxhp = b.hp;
		if (allowRider && Random(0, 99) < 28)
		{
			let r = RRecruit(Actor.Spawn("RRecruit", b.pos + (0, 0, 32)));
			if (r)
			{
				r.host = b;
				b.rider = r;
				extras.Push(r);
			}
		}
	}
}
