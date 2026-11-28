our %h = (a=>1); our $x = 1; { local ($x, %h) = (2, b=>2); } print $x, join(",", keys %h), "\n";
