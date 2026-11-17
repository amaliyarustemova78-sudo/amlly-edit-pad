-- AMLLYEDIT PAD v5 - TAM SUPABASE BULUT VERITABANI KURULUMU
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    custom_shortcuts JSONB DEFAULT '{
        "split": "Ctrl+B",
        "razor_all": "Ctrl+Shift+K",
        "trim_head": "Q",
        "trim_tail": "W",
        "undo": "Ctrl+Z",
        "redo": "Ctrl+Y",
        "select_forward": "A",
        "rate_stretch": "R",
        "match_frame": "F",
        "marker": "M",
        "default_transition": "Ctrl+D",
        "paste_attributes": "Ctrl+Alt+V"
    }'::jsonb,
    saved_presets JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.projects (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL DEFAULT 'AmllyEdit Kurgu Projesi',
    active_sequence_index INTEGER NOT NULL DEFAULT 0,
    playhead_position_ms BIGINT NOT NULL DEFAULT 0,
    aspect_ratio TEXT NOT NULL DEFAULT '16:9',
    fps INTEGER NOT NULL DEFAULT 60,
    resolution TEXT NOT NULL DEFAULT '1080p',
    sequences_state JSONB NOT NULL DEFAULT '[]'::jsonb,
    version_sequence BIGINT NOT NULL DEFAULT 1,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.project_media_assets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    clip_id TEXT NOT NULL,
    local_file_path TEXT NOT NULL,
    proxy_file_path TEXT,
    cloud_backup_url TEXT,
    ai_processed_url TEXT,
    ai_status TEXT DEFAULT 'ready',
    duration_ms BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_projects_user_sync ON public.projects(user_id, last_synced_at DESC);
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_media_assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanici kendi profilini yonetir" ON public.user_profiles FOR ALL USING (auth.uid() = id);
CREATE POLICY "Kullanici kendi projelerini yonetir" ON public.projects FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Kullanici kendi medyalarini yonetir" ON public.project_media_assets FOR ALL USING (auth.uid() = user_id);
