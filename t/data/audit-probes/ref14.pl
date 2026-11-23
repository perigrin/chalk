my $x=0; my $f=sub { $x++ }; my $y = $f->() + $f->()*10 + $x*100; print "$y\n";
