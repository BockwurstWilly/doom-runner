// Options menu: graphics presets and the Brutal Doom gore setting

// "Grafik: Niedrig / Mittel / Hoch" - choosing a preset sets the engine cvars right away
class OptionMenuItemRunnerGfxOption : OptionMenuItemOption
{
	override void SetSelection(int selection)
	{
		Super.SetSelection(selection);
		Apply(selection);
	}

	static void SetC(Name n, double v)
	{
		let c = CVar.FindCVar(n);
		if (!c) return;
		if (c.GetRealType() == CVar.CVAR_Float) c.SetFloat(v);
		else c.SetInt(int(v));
	}

	static void Apply(int p)
	{
		//                     low    mid    high
		static const double lights[]  = { 0,   1,   1 };
		static const double bloom[]   = { 0,   0,   1 };
		static const double ssao[]    = { 0,   0,   1 };
		static const double fxaa[]    = { 0,   1,   2 };
		static const double aniso[]   = { 1,   4,  16 };
		static const double scale[]   = { 0.75, 1, 1 };
		static const double decals[]  = { 128, 512, 2048 };
		p = clamp(p, 0, 2);
		SetC('gl_lights', lights[p]);
		SetC('gl_bloom', bloom[p]);
		SetC('gl_ssao', ssao[p]);
		SetC('gl_fxaa', fxaa[p]);
		SetC('gl_texture_filter_anisotropic', aniso[p]);
		SetC('vid_scalefactor', scale[p]);
		SetC('cl_maxdecals', decals[p]);
	}
}

// "Gore": only offered when Brutal Doom is loaded; drives its blood amount plus
// how often Doom Runner kills end in a full gib
class OptionMenuItemRunnerGoreOption : OptionMenuItemOption
{
	override void SetSelection(int selection)
	{
		Super.SetSelection(selection);
		static const int gibs[] = { 512, 1024, 2048, 4096 };
		let c = CVar.FindCVar('sv_corpsequeuesize');
		if (c) c.SetInt(gibs[clamp(selection, 0, 3)]);
		EventHandler.SendNetworkEvent("rr_goreapply");
	}
}

class RunnerOptionsMenu : OptionMenu
{
	override void Init(Menu parent, OptionMenuDescriptor desc)
	{
		if (!CVar.FindCVar('zdoombrutalblood'))
		{
			for (int i = desc.mItems.Size() - 1; i >= 0; i--)
			{
				if (desc.mItems[i] is "OptionMenuItemRunnerGoreOption") desc.mItems.Delete(i);
			}
		}
		Super.Init(parent, desc);
	}

	mixin RunnerMenuCursor;

	override bool OnUIEvent(UIEvent ev)
	{
		CursorEvent(ev);
		bool res = Super.OnUIEvent(ev);
		CursorAfter();
		return res;
	}

	override bool MenuEvent(int mkey, bool fromcontroller)
	{
		bool res = Super.MenuEvent(mkey, fromcontroller);
		CursorAfter();
		return res;
	}

	override void Drawer()
	{
		Super.Drawer();
		DrawSoftCursor();
	}
}

// big software mouse cursor for Doom Runner's own menus
mixin class RunnerMenuCursor
{
	int curX, curY;
	bool curOn;

	void CursorEvent(UIEvent ev)
	{
		if (ev.type > UIEvent.Type_FirstMouseEvent && ev.type < UIEvent.Type_LastMouseEvent)
		{
			curX = ev.MouseX;
			curY = ev.MouseY;
			curOn = true;
		}
	}

	// after the menu handled input: if a different (engine) menu took over or the menu
	// closed, give the system cursor back, otherwise keep it hidden behind ours
	void CursorAfter()
	{
		RunnerMainMenu.SetOSCursor(curOn && Menu.GetCurrentMenu() == self);
	}

	void DrawSoftCursor()
	{
		if (!curOn) return;
		TextureID t = TexMan.CheckForTexture("RCURS3", TexMan.Type_Any);
		if (!t.IsValid()) return;
		double s = Screen.GetHeight() * 0.06;
		Screen.DrawTexture(t, false, curX, curY, DTA_DestWidthF, s, DTA_DestHeightF, s);
	}
}

// main menu entry "SPRACHE: DEUTSCH" / "LANGUAGE: ENGLISH" - toggles the GZDoom language
class ListMenuItemRunnerLangItem : ListMenuItemTextItem
{
	override bool Activate()
	{
		Menu.MenuSound("menu/choose");
		bool german = StringTable.Localize("$RR_LANGID") == "de";
		let c = CVar.FindCVar('language');
		if (c) c.SetString(german ? "enu" : "de");
		return true;
	}
}

