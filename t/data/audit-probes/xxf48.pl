our $g = 1; sub rd { $g } my @l = grep { local $g = $_; rd() > 1 } 1..3; print "@l$g\n";
