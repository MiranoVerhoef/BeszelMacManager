# Beszel Mac Manager

A small macOS helper app to manage the **Beszel Agent** on a Mac.

This manager is intentionally “easy mode”: it assumes you use **Homebrew**, so service control is done through `brew services` (launchd under the hood).

## What it does

- Edit & save Beszel Agent env vars:
  - `KEY`, `TOKEN`, `HUB_URL`, `LISTEN`
- Start / Stop / Restart the agent service via Homebrew
- Install / update the agent via Homebrew
- Show the agent log (tail view)
- Shows the app version in the UI + window title so you know what build you’re running

## Requirements

- macOS
- Homebrew

If Homebrew isn’t installed yet, the app has a button that opens Terminal and runs the official Homebrew installer.

## Files & paths

This app only uses these paths in your home folder:

- Env file: `~/.config/beszel/beszel-agent.env`
- Log file: `~/.cache/beszel/beszel-agent.log`

## Install Beszel Agent (Homebrew)

You can install from the app, or run it yourself:

```bash
brew tap henrygd/beszel
brew install beszel-agent
brew services start beszel-agent
