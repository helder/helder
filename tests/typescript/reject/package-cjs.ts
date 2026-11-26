/* expect: TSHX001: cjs-pkg is CommonJS, which helder does not compile yet */
import {x} from "cjs-pkg";
console.log(x);
