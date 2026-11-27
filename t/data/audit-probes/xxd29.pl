my $x=1; my $f = sub { my $r = \$_[0]; sub { $$r++ } }; my $inc = $f->($x); $inc->(); $inc->(); print "$x\n";
