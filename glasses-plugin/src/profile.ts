import type { PluginProfile } from 'even-companion-plugin'

export const profile: PluginProfile = {
  name: 'Borderless',
  companionPort: 8767,
  pages: [],
  micControl: false,
  startupText: 'Borderless\n\nOpen Borderless on this phone\nand enable the G2 display.',
  idleText: () => 'Borderless connected\n\nYour conversation will appear here.',
  steps: ['Open Borderless on this phone', 'Enable the G2 display', 'Start the conversation'],
}
