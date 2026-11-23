my $x=1; my $r=\$x; my $f=sub { $$r=9 }; my $y="$x"; $f->(); print "$y $x\n";
