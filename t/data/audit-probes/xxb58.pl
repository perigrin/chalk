our @g=(1,2,3); sub z { for (@g) { $_++ } } for (@g) { z() if $_ == 1 } print "@g\n";
