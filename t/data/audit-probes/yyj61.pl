my $v = "file"; { package Other; sub get { $v } } print Other::get(), "\n";
