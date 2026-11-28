sub mk { my $r = \$_[0]; sub { $$r++ } } my $v = 1; my $c = mk($v); $c->(); print "$v\n";
