our @arr = (1,2); *ALIAS = \@arr; our @ALIAS; $ALIAS[0] = 9; print "@arr\n";
