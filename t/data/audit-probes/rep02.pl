our $g=1; my $r = eval { local $g = 2; 5 }; print "$g $r\n";
