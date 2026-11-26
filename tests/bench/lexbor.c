// lexbor's parse of each file, the least time of runs (bench html): a JSON
// line a file, as HtmlBench.hx prints them.
//
//   bin/bench/lexbor/bench <runs> <file.html> ...
#include <lexbor/html/parser.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(int argc, char **argv) {
	int runs = atoi(argv[1]);
	for (int a = 2; a < argc; a++) {
		FILE *f = fopen(argv[a], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
		unsigned char *buf = malloc(n); fread(buf, 1, n, f); fclose(f);
		double best = 1e9;
		for (int r = 0; r < runs; r++) {
			double t0 = now();
			lxb_html_document_t *doc = lxb_html_document_create();
			lxb_html_document_parse(doc, buf, n);
			double t = now() - t0;
			lxb_html_document_destroy(doc);
			if (t < best) best = t;
		}
		printf("{\"file\":\"%s\",\"bytes\":%ld,\"ms\":%.3f}\n", argv[a], n, best * 1000);
		free(buf);
	}
	return 0;
}
