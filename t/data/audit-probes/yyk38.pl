use feature 'class'; no warnings; class P { field $n :param; method mk { sub { $n++ } } method n { $n } } my $o = P->new(n => 1); my $f = $o->mk; $f->(); $f->(); print $o->n, "\n";
