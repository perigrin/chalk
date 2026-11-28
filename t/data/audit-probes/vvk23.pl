sub f { wantarray ? "l" : "s" } print f(), " ", "" . f(), " ", (f())[0], " ", scalar(f()), "\n";
