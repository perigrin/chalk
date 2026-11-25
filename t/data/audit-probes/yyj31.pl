use feature 'state'; sub c { state %seen; $seen{$_[0]}++ ? "dup" : "new" } print c("a"), c("b"), c("a"), "\n";
