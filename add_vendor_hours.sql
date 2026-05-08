-- Add opening time to vendors table
ALTER TABLE public.vendors 
ADD COLUMN IF NOT EXISTS opening_time TEXT DEFAULT '09:00';
