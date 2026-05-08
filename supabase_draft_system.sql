-- 1. Create Draft Addresses Table
-- This table stores intermediate selections so user_addresses stays clean until "Continue" is pressed.

CREATE TABLE IF NOT EXISTS public.user_address_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    area_id UUID REFERENCES public.delivery_areas(id) ON DELETE SET NULL,
    address_line_1 TEXT,
    location GEOGRAPHY(POINT),
    building_number TEXT,
    floor_number TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_draft_user UNIQUE (user_id)
);

-- 2. Update orchestration function to work with DRAFTS
-- This function identifies the nearest delivery area and saves it to the DRAFT table.

CREATE OR REPLACE FUNCTION public.set_user_address_draft(
    p_street TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
) RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_area_id UUID;
    v_area_name TEXT;
    v_result JSONB;
BEGIN
    -- 1. Get current user ID
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;

    -- 2. Find the nearest delivery area
    SELECT id, name INTO v_area_id, v_area_name
    FROM public.delivery_areas
    WHERE location IS NOT NULL
      AND is_active = true
    ORDER BY location <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    LIMIT 1;

    -- 3. UPSERT into Draft table
    INSERT INTO public.user_address_drafts (
        user_id,
        area_id,
        address_line_1,
        location
    ) VALUES (
        v_user_id,
        v_area_id,
        p_street,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    )
    ON CONFLICT (user_id) 
    DO UPDATE SET
        area_id = EXCLUDED.area_id,
        address_line_1 = EXCLUDED.address_line_1,
        location = EXCLUDED.location,
        created_at = NOW()
    RETURNING jsonb_build_object(
        'area_id', area_id,
        'area_name', v_area_name,
        'street', address_line_1
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to FINALIZE from draft to user_addresses
-- This is called when user clicks "Continue"

CREATE OR REPLACE FUNCTION public.finalize_user_address(
    p_building TEXT,
    p_floor TEXT
) RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_draft RECORD;
BEGIN
    v_user_id := auth.uid();
    
    -- Get draft data
    SELECT * INTO v_draft FROM public.user_address_drafts WHERE user_id = v_user_id;
    
    IF v_draft IS NULL THEN
        RAISE EXCEPTION 'No draft address found';
    END IF;

    -- UPSERT into main user_addresses
    INSERT INTO public.user_addresses (
        user_id,
        area_id,
        address_line_1,
        building_number,
        floor_number,
        location,
        is_default,
        title
    ) VALUES (
        v_user_id,
        v_draft.area_id,
        v_draft.address_line_1,
        p_building,
        p_floor,
        v_draft.location,
        true,
        'منزل'
    )
    ON CONFLICT (user_id) 
    DO UPDATE SET
        area_id = EXCLUDED.area_id,
        address_line_1 = EXCLUDED.address_line_1,
        building_number = EXCLUDED.building_number,
        floor_number = EXCLUDED.floor_number,
        location = EXCLUDED.location,
        is_default = true,
        created_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
