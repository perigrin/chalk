our @g=(1,2,3); sub z { $_ = 0 } my @b = map { z(); 1 } @g; print "@g\n";
