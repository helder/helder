package helder.asset;

// What helder/asset's model(path) gives a TypeScript program: helder/scene's
// Model where the program has helder/scene (its declarations add `model` to
// Models: src/helder/scene/index.ts), else unknown. So helder/asset's
// declarations name no type of helder/scene's, and a program of helder/ui
// alone neither reads helder/scene's nor types its declaration class (its
// manifest: seconds of every build).
interface Models {}

// (Models' model, when added)
@:typescript.type("Models extends {model: infer M} ? M : unknown")
typedef ModelOf = Dynamic;
