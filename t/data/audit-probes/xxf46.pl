our $g = 1; my @l = map { local $g = $_; $g * 2 } 1..3; print "@l$g\n";
