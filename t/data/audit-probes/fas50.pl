our $x=1; sub n { $x=7 } my $s="$x-@{[n()]}-$x"; print "$s\n";
