sub f { wantarray ? "l" : "s" } my $s = join(",", f(), map { f() } 1); my @t = sort(f()); if (f()) { print "$s@t" } print "\n";
