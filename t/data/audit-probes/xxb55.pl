our @g=(1,2,3); sub z { $_[0]++ } z($_) for @g; print "@g\n";
