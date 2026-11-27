our $g = 1; sub rd { $g } my @l = map { local $g = $_; rd() } 1..3; print "@l$g\n";
