my $x = 1; eval { eval 'die "in\n"'; $x = 2 if $@ }; print "$x\n";
