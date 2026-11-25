our $g=1; sub p { print $g } for (local $g = 0; $g < 2; $g++) { p() } p(); print "\n";
