package helder.dom;

// A parse error: the HTML standard's code (the tokenizer's, as the spec
// names them; the tree builder's are this parser's own) and the source
// offset where it was found.
typedef ParseError = {code:String, offset:Int};
