sub r { "<$_[0]>" } my $s="abc"; my @a=(1,2); print r(substr($s,1,1)), r($#a), "\n";
