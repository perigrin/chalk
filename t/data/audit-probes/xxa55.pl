sub f { wantarray ? "l" : defined(wantarray) ? "s" : "v" } my @r = (f(), scalar(f())); f(); print "@r\n";
