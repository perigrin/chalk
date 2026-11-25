sub inc { $_[0]++ } my $x=1; my $r=\$x; inc($$r); inc(${\ $x}); print "$x\n";
