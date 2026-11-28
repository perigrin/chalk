sub mk { my $r = shift; sub { $$r++ } } my $v = 1; my $c = mk(\$v); $c->(); print "$v\n";
