use feature "state"; sub c { state $n; $n.="x"; $n } c(); print c(),"\n";
