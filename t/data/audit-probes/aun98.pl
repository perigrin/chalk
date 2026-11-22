our $g = 1; my $r = eval { local $g = 2; $g + 1 }; print "$g $r\n";
