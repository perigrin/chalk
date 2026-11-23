use feature "state"; sub c { state %h; $h{$_[0]}++; scalar keys %h } c("a"); print c("b"),"\n";
