my $x=0; my $f=sub { $x=1; 5 }; my $v = $x + $f->() + $x; print "$v\n";
