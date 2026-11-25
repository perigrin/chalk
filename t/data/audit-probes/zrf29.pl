my $x=1; my $r=\$x; my $s=sub { $x+1 }; $$r=5; print $s->(), "\n";
