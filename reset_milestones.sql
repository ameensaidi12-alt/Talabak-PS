-- [RESET] Run this to allow users to earn milestones again after a leaderboard reset
-- This command clears the list of "Already Won" milestones for all users for the 'into-space' game.

UPDATE public.game_progress 
SET won_milestones = '[]' 
WHERE game_slug = 'into-space';

-- Note: To reset for a specific user ONLY:
-- UPDATE public.game_progress SET won_milestones = '[]' WHERE game_slug = 'into-space' AND user_id = 'USER_ID_HERE';
