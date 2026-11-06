// Player, camera, dummy weapon, empty status bar

class RunnerPlayer : DoomPlayer
{
	Default
	{
		Player.StartItem "RunnerNoGun";
		Player.DisplayName "Runner";
		Player.ViewBob 0;
		+NODAMAGE
	}

	// real Doom/Brutal Doom enemy projectiles (imp fireballs) hit us here
	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		let h = RunnerHandler.Get();
		if (h && source is "REnemy" && !(flags & DMG_EXPLOSION)) h.DamagePlayer(source is "RImp" ? 2 : 1);
		return 0;
	}

	override void MovePlayer()
	{
		let h = RunnerHandler.Get();
		Angle = 90;
		if (!h || h.phase != 1)
		{
			Vel.X = 0;
			Vel.Y = 0;
			if (h && h.phase == 0 && InStateSequence(CurState, SeeState)) SetState(SpawnState);
			return;
		}

		UserCmd cmd = player.cmd;
		double side = clamp(cmd.sidemove / 6144.0, -1.0, 1.0);
		double turn = cmd.yaw * (360.0 / 65536.0);
		double vx = clamp(side * 10.0 - turn * 2.0, -14.0, 14.0);
		if (CVar.FindCVar('rr_autotest').GetInt() > 0) vx = TestBotSteer(h); // test bot only
		if (pos.x + vx > RR_HALF) vx = RR_HALF - pos.x;
		if (pos.x + vx < -RR_HALF) vx = -RR_HALF - pos.x;
		Vel.X = vx;
		Vel.Y = h.runSpeed;

		bool moving = h.runSpeed > 0 || abs(vx) > 0.5;
		if (moving && InStateSequence(CurState, SpawnState)) SetState(SeeState);
		else if (!moving && InStateSequence(CurState, SeeState)) SetState(SpawnState);
	}

	// simple test bot (cvar rr_autotest): steer towards the nearest enemy ahead
	double TestBotSteer(RunnerHandler h)
	{
		double best = 1e9, tx = 0;
		for (int i = 0; i < h.targets.Size(); i++)
		{
			let t = h.targets[i];
			if (!t || t.dead || !(t is "REnemy" || t is "RCrate")) continue;
			double dy = t.pos.y - pos.y;
			if (dy > 0 && dy < best) { best = dy; tx = t.pos.x; }
		}
		for (int i = 0; i < h.extras.Size(); i++)
		{
			let x = h.extras[i];
			if (!(x is "RPickup")) continue;
			double dy = x.pos.y - pos.y;
			if (dy > 0 && dy < best) { best = dy; tx = x.pos.x; }
		}
		return clamp((tx - pos.x) * 0.2, -7.0, 7.0);
	}

	States
	{
	Fallen:
		PLAY H 5;
		PLAY I 5;
		PLAY J 5;
		PLAY K 5;
		PLAY L 5;
		PLAY M 5;
		PLAY N -1;
		stop;
	}
}

class RunnerCam : Actor
{
	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
		+NOGRAVITY
		RenderStyle "None";
		CameraHeight 0;
		CameraFOV 90;
	}

	double camBack, camUp, camPitch;

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		if (camBack == 0) SetView(190, 150, 22);
	}

	void SetView(double back, double up, double ptch)
	{
		camBack = back;
		camUp = up;
		camPitch = ptch;
	}

	override void Tick()
	{
		let fc = CVar.FindCVar('rr_camfov');   // video / portrait helper, default 90
		CameraFOV = fc ? clamp(fc.GetFloat(), 30.0, 120.0) : 90.0;
		if (target) SetOrigin(target.pos + (0, -camBack, camUp), true);
		Angle = 90;
		Pitch = camPitch;
	}

	void Snap()
	{
		if (target) SetOrigin(target.pos + (0, -camBack, camUp), false);
		Angle = 90;
		Pitch = camPitch;
		ClearInterpolation();
	}

	States
	{
	Spawn:
		TNT1 A -1;
		stop;
	}
}

class RunnerNoGun : Weapon
{
	Default
	{
		Weapon.SelectionOrder 1;
		+WEAPON.NOALERT
		+WEAPON.CHEATNOTWEAPON
		+INVENTORY.UNDROPPABLE
	}

	States
	{
	Spawn:
		TNT1 A -1;
		stop;
	Ready:
		TNT1 A 1 A_WeaponReady(WRF_NOFIRE);
		loop;
	Select:
		TNT1 A 1 A_Raise;
		loop;
	Deselect:
		TNT1 A 1 A_Lower;
		loop;
	Fire:
		TNT1 A 1;
		goto Ready;
	}
}

class RunnerStatusBar : BaseStatusBar
{
	override void Init()
	{
		Super.Init();
		SetSize(0, 320, 200);
	}

	override void Draw(int state, double TicFrac)
	{
	}
}
