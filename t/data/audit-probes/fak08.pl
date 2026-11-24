my $x=1; my $f=sub { $x*=2 }; $f->() for 1..3; print "$x\n";
