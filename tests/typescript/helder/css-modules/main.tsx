import styles from './card.module.css'
import './base.module.css'
import alias from '@styles/card.module.css'
import reexported from './names'
import base from './base.module.css'
import { Static } from 'helder/web'
import { CssModuleProbe } from './probe'

const card = <div class={styles['card-title']}>card</div>
const html = Static.render(card)
console.log(CssModuleProbe.measure(html))
console.log(html.replace(styles['card-title'], 'scoped composed'))
console.log(styles['card-title'].split(' ')[1] === base.base, styles === alias, styles === reexported)
console.log(styles.default.startsWith('card_default_'), styles.cardTitle.startsWith('card_cardTitle_'), Object.isFrozen(styles))
console.log(styles.__proto__.startsWith('card___proto___'))
