# Simple Votekick
## An addon for Garry's Mod

This is an addon for Garry's Mod that allows players to call a vote to kick a
player from the server.

### Chat commands

 +   **!votekick** - Open the player selection menu.
 +   **!yes** - Vote 'Yes' on an active vote.
 +   **!no** - Vote 'No' on an active vote.

### Conditions to pass a vote

 +   Enough players participated in the voting.
 +   More people agreed to vote off the player than those who didn't.

### Configuration

 +   **Voting menu**
  +   _Q menu_ > Options > DyaMetR > Simple Votekick System
 +   **Settings menu**
  +   _Q menu_ > Utilities > DyaMetR > Simple Votekick System

### Server settings

 +   **sv_votekick** - Enables the addon. Disabling it during a vote will cancel it.
 +   **sv_votekick_immuneadmins** - Doesn't allow players to vote admins off.
 +   **sv_votekick_bantime** - How long is a player banned when voted off.
 +   **sv_votekick_votetime** - How long does a voting last for.
 +   **sv_votekick_cooldown** - How long has a player need to wait before calling another vote.
 +   **sv_votekick_minvotes** - Minimum percentage of players that need to partake in the voting for it to be valid.
 +   **sv_votekick_minplayers** - Minimum amount of players required for a vote to be called.

### Aborting a vote

As an administrator, you may want to prematurely end a vote because, to do this
you can either go to the [settings menu](#configuration) and press **_Abort current vote_**
or write **_votekick_abort_** in the console.

### Developer documentation

If you want to customize the look and sounds of this addon, either to release it
as a mod or for your own server, you can use the following hooks:

> **VotekickHUDPaint**
>
> Called when the UI should draw. Return **true** to hide the default HUD.
>
> _Parameters_
>
> +   the voting information table

> **VotekickBeginSound**
>
> Called when the vote starts to play the given sound. Return **true** to mute it.

> **VotekickVoteSound**
>
> Called when a player votes.
>
> _Parameters_
>
> +   was it a positive vote
> +   is it an increment

> **VotekickSuccessSound**
>
> Called when a vote is successful to play the given sound. Return **true** to mute it.

> **VotekickFailSound**
>
> Called when a vote fails to play the given sound. Return **true** to mute it.

> **VotekickAbortSound**
>
> Called when a vote is aborted to play the given sound. Return **true** to mute it.

## Have fun!
