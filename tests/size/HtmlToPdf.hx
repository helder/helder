import helder.cli.Options;
import helder.cli.PdfCommand;

class HtmlToPdf {
	static function main()
		Sys.exit(PdfCommand.run(Options.parse("pdf", Sys.args())));
}
