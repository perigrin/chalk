sub f { return } my @l = map { f() } 1..3; print scalar(@l), "\n";
