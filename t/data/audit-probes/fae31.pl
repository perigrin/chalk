use feature 'try'; no warnings; sub f { my $x=shift; try { die "a\n" if $x; return "ok" } catch ($e) { return "c:$e" } } print f(0), f(1);
