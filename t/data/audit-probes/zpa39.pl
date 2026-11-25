my $x=1; my %d=(s=>sub { $_[0]=4 }); $d{s}->($x); print "$x\n";
