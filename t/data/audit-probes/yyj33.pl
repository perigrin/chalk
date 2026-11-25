our $g=1; sub p { print $g } my $c=1; { local $g = 5 if $c; p() } p(); print "\n";
