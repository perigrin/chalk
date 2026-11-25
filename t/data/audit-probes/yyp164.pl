our $g=1; my $r=\$g; { local $g=5; $$r=7; print $g } print "$g\n";
