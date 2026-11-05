import { startPlugin } from 'even-companion-plugin'
import { profile } from './profile'
import 'even-companion-plugin/plugin.css'

startPlugin(profile, document.getElementById('plugin-root') ?? document.body)
