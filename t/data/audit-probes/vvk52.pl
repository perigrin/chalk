$_ = 5; sub f { $_++ } for (1..2) { f() } print "$_\n";
