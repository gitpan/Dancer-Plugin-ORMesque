#ABSTRACT: Light ORM for Dancer

package Dancer::Plugin::ORMesque;
BEGIN {
  $Dancer::Plugin::ORMesque::VERSION = '1.103070';
}

use strict;
use warnings;
use base 'DBIx::Simple';

use Dancer qw/:syntax/;
use Dancer::Plugin;
use Dancer::Plugin::Database;
use Dancer::Plugin::ORMesque::SchemaLoader;

use SQL::Abstract;
use SQL::Interp;

our $Cache = undef;



register dbi => sub {
    
    return $Cache if $Cache;
    
    my $cfg  = config->{plugins}->{Database};
    my $dbh  = database;
    my $self = {};
    my $this = {};
    
    bless $self, 'Dancer::Plugin::ORMesque';

    warn "Error connecting to the database..." unless $dbh;
    warn "No database driver specified in the configuration file"
      unless $cfg->{driver};

    # POSTGRESQL CONFIGURATION
    $this = Dancer::Plugin::ORMesque::SchemaLoader
    ->new($dbh)->mysql if lc($cfg->{driver}) =~ '^postgre(s)?(ql)?$';
    

    # MYSQL CONFIGURATION
    $this = Dancer::Plugin::ORMesque::SchemaLoader
    ->new($dbh)->mysql if lc($cfg->{driver}) eq 'mysql';

    # SQLite CONFIGURATION
    $this = Dancer::Plugin::ORMesque::SchemaLoader
    ->new($dbh)->sqlite if lc($cfg->{driver}) eq 'sqlite';
    
    $self->{schema} = $this->{schema};
    die "Could not read the specified database $cfg->{driver}"
        unless @{$self->{schema}->{tables}};

    # setup reuseable connection using DBIx::Simple
    $self->{dbh} = DBIx::Simple->connect($dbh) or die DBIx::Simple->error;
    $self->{dbh}->result_class = 'DBIx::Simple::Result';

    # define defaults
    $self->{target} = '';

    # create base accessors
    no warnings 'redefine';
    no strict 'refs';

    foreach my $table (@{$self->{schema}->{tables}}) {

        my $class        = ref($self);
        my $method       = $class . "::" . lc $table;
        my $package_name = $class . "::" . ucfirst $table;
        my $package      = "package $package_name;" . q|
            
            use base 'Dancer::Plugin::ORMesque';
            
            sub new {
                my ($class, $base, $table) = @_;
                my $self            = {};
                bless $self, $class;
                $self->{table}      = $table;
                $self->{where}      = {};
                $self->{order}      = [];
                $self->{key}        = $base->{schema}->{table}->{$table}->{primary_key};
                $self->{collection} = [];
                $self->{cursor}     = 0;
                $self->{current}    = {};
                $self->{schema}     = $base->{schema};
                $self->{dbh}        = $base->{dbh};
                
                # build database objects
                $self->{configuration} = $cfg;
                
                foreach my $column (@{$self->{schema}->{table}->{$table}->{columns}}) {
                    $self->{current}->{$column} = '';
                    my $attribute = $class . "::" . $column;
                    *{$attribute} = sub {
                        my ($self, $data) = @_;
                        if (defined $data) {
                            $self->{current}->{$column} = $data;
                            return $data;
                        }
                        else {
                            return
                                $self->{current}->{$column};
                        }
                    };
                }
                
                return $self;
            }
            1;
            |;
        eval $package;
        die print $@ if $@;    # debugging
        *{$method} = sub {
            return $package_name->new($self, $table);
        };

        # build dbo table

    }
    
    $Cache = $self;
    return $self;
};


sub reset {
    $Cache = undef;
}


sub next {
    my $dbo = shift;

    my $next =
      $dbo->{cursor} <= (int(@{$dbo->{collection}}) - 1) ? $dbo : undef;
    $dbo->{current} = $dbo->{collection}->[$dbo->{cursor}] || {};
    $dbo->{cursor}++;

    return $next;
}


sub first {
    my $dbo = shift;

    $dbo->{cursor} = 0;
    $dbo->{current} = $dbo->{collection}->[0] || {};

    return $dbo->current;
}


sub last {
    my $dbo = shift;

    $dbo->{cursor} = (int(@{$dbo->{collection}}) - 1);
    $dbo->{current} = $dbo->{collection}->[$dbo->{cursor}] || {};

    return $dbo->current;
}


sub collection {
    return shift->{collection};
}


sub current {
    return shift->{current};
}


sub clear {
    my $dbo = shift;

    foreach my $column (keys %{$dbo->{current}}) {
        $dbo->{current}->{$column} = '';
    }

    $dbo->{collection} = [];

    return $dbo;
}


sub key {
    shift->{key};
}


sub return {
    my $dbo   = shift;
    my %where = %{$dbo->current};

    delete $where{$dbo->key} if $dbo->key;

    $dbo->read(\%where)->last;

    return $dbo->current;
}


sub count {
    my $dbo = shift;
    return scalar @{$dbo->{collection}};
}


sub create {
    my $dbo     = shift;
    my $input   = shift || {};
    my @columns = keys %{$dbo->{current}};

    die
      "Cannot create an entry in table ($dbo->{table}) without any input parameters."
      unless keys %{$input};

    # process direct input
    if ($input) {
        foreach my $i (keys %{$input}) {
            if (defined $dbo->{current}->{$i}) {
                $dbo->{current}->{$i} = $input->{$i};
            }
        }
    }

    # insert
    $dbo->{dbh}->insert($dbo->{table}, $dbo->{current});

    return $dbo;
}


sub read {
    my $dbo     = shift;
    my $where   = shift || {};
    my $order   = shift || [];
    my $table   = $dbo->{table};
    my @columns = keys %{$dbo->{current}};

    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }

    $dbo->{resultset} = sub {
        return $dbo->{dbh}->select($table, \@columns, $where, $order);
    };
    $dbo->{collection} = $dbo->{resultset}->()->hashes;
    $dbo->{cursor}     = 0;
    $dbo->next;

    return $dbo;
}


sub update {
    my $dbo     = shift;
    my $input   = shift || {};
    my $where   = shift || {};
    my $table   = $dbo->{table};
    my @columns = keys %{$dbo->{current}};

    # process direct input
    die
      "Attempting to update an entry in table ($dbo->$table) without any input."
      unless keys %{$input};

    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }

    $dbo->{dbh}->update($table, $input, $where) if keys %{$input};

    return $dbo;
}


sub delete {
    my $dbo   = shift;
    my $where = shift || {};
    my $table = $dbo->{table};

    # process where clause
    if (ref($where) eq "HASH") { }
    elsif ($where && $dbo->key && ref($where) ne "HASH") {
        $where = {$dbo->key => $where};
    }
    else {
        die "Cannot delete without a proper where clause, "
          . "use delete_all to purge the entire database table";
    }

    $dbo->{dbh}->delete($table, $where);

    return $dbo;
}


sub delete_all {
    my $dbo   = shift;
    my $table = $dbo->{table};

    $dbo->{dbh}->delete($table);

    return $dbo;
}




sub columns {
    shift->{resultset}->()->columns(@_);
}


sub into {
    return shift->{resultset}->()->into(@_);
}


sub list {
    return shift->{resultset}->()->list(@_);
}


sub array {
    return shift->{resultset}->()->array(@_);
}


sub hash {
    return shift->{resultset}->()->hash(@_);
}


sub flat {
    return shift->{resultset}->()->flat(@_);
}


sub arrays {
    return shift->{resultset}->()->arrays(@_);
}


sub hashes {
    return shift->{resultset}->()->hashes(@_);
}


sub map_hashes {
    return shift->{resultset}->()->map_hashes(@_);
}


sub map_arrays {
    return shift->{resultset}->()->map_arrays(@_);
}


sub rows {
    return shift->{resultset}->()->rows(@_);
}


sub query {
    return shift->{dbh}->query(@_);
}


sub iquery {
    return shift->{dbh}->iquery(@_);
}


register_plugin;

1;

__END__
=pod

=head1 NAME

Dancer::Plugin::ORMesque - Light ORM for Dancer

=head1 VERSION

version 1.103070

=head1 SYNOPSIS

Dancer::Plugin::ORMesque is a lightweight ORM for Dancer supporting any database
listed under L<Dancer::Plugin::ORMesque::SchemaLoader> making it a great alternative
to L<Dancer::Plugin::Database> if you are looking for a bit more automation and a fair
alternative to Dancer::Plugin::DBIC when you don't have the time, need or desire to learn
L<Dancer::Plugin::DBIC> and L<DBIx::Class>. Dancer::Plugin::ORMesque is an
object relational mapper for Dancer that provides a database connection to the
database of your choice and automatically creates objects and accessors for that
database and its tables and columns. Dancer::Plugin::ORMesque uses
L<SQL::Abstract> querying syntax.

Connection details will be taken from your Dancer application config file,
and should be specified as, for example:

    plugins:
      Database:
        driver: 'mysql'
        database: 'test'
        host: 'localhost'
        username: 'myusername'
        password: 'mypassword'
        connectivity-check-threshold: 10
        dbi_params:
            RaiseError: 1
            AutoCommit: 1
        on_connect_do: ["SET NAMES 'utf8'", "SET CHARACTER SET 'utf8'" ]

NOTE! In your configuration file, under plugins, the plugin that should be
configured is 'Database' and not 'ORMesque'.

The connection functionality is imported from L<Dancer::Plugin::Database>, please
look into that plugin for more information. Please note that even if you use supply
a DSN directly in your configuration file you need to also specify a driver directive.

    # Use the dbi (database interface) keyword to establish a new connection to
    # the database then access users (the users table) and store the reference in
    # local variable $users
    
    my $user = dbi->users;
    
    # Grab the first record, not neccessary if operating on only one record
    
    $user->read;
    
    # SQL::Abstract where clause passed to the "read" method
    
    $user->read({
        'column' => 'query'
    });
    
    $user->first;
    $user->last;
    
    # How many records in collection
    
    $user->count
    
    for (0..$user->count) {
        print $user->column;
        $user->column('new stuff');
        $user->update($user->current, $user->id);
        $user->next;
    }
    
    # The database objects main accessors are CRUD (create, read, update, and delete)
    
    $user->create;
      $user->read;
        $user->update;
          $user->delete;
    
    # Also, need direct access to the resultset?
    
    $user->collection; # returns an array of hashrefs
    $user->current;    # return a hashref of the current row in the collection

=head2 dbi

    The dbi method/keyword instantiates a new Dancer::Plugin::ORMesque instance
    which uses the datasource configuration details in your configuration file
    to create database objects and accessors.
    
    my $db = dbi;

=head2 reset

    Once the dbi() keyword analyzes the specified database, the schema is cached
    to for speed and performance. Occassionally you may want to re-read the
    database schema.
    
    dbi->reset;
    my $db = dbi;

=head2 next

    The next method instructs the database object to continue to the next
    row if it exists.
    
    dbi->table->next;
    
    while (dbi->table->next) {
        ...
    }

=head2 first

    The first method instructs the database object to continue to return the first
    row in the resultset.
    
    dbi->table->first;

=head2 last

    The last method instructs the database object to continue to return the last
    row in the resultset.
    
    dbi->table->last;

=head2 collection

    The collection method return the raw resultset object.
    
    dbi->table->collection;

=head2 current

    The current method return the raw row resultset object of the position in
    the resultset collection.
    
    dbi->table->current;

=head2 clear

    The clear method empties all resultset containers. This method should be used
    when your ready to perform another operation (start over) without initializing
    a new object.
    
    dbi->table->clear;

=head2 key

    The key method finds the database objects primary key if its defined.
    
    dbi->table->key;

=head2 return

    The return method queries the database for the last created object(s).
    It is important to note that while return() can be used in most cases
    like the last_insert_id() to fetch the recently last created entry,
    function, you should not use it that way unless you know exactly what
    this method does and what your database will return.
    
    my $new_record = dbi->table->create(...)->return();

=head2 count

    The count method returns the number of items in the resultset of the
    object it's called on. Note! If you make changes to the database, you
    will need to call read() before calling count() to get an accurate
    count as count() operates on the current collection.
    
    my $count = dbi->table->read->count;

=head2 create

    Caveat 1: The create method will remove the primary key if the column
    is marked as auto-incremented ...
    
    The create method creates a new entry in the datastore.
    takes 1 arg: hashref (SQL::Abstract fields parameter)
    
    dbi->table->create({
        'column_a' => 'value_a',
    });
    
    # create a copy of an existing record
    my $user = dbi->users;
    $user->read;
    $user->full_name_column('Copy of ' . $user->full_name);
    $user->user_name_column('foobarbaz');
    $user->create($user->current);

    # get newly created record
    $user->return;
    
    print $user->id; # new record id
    print $user->full_name;

=head2 read

    The read method fetches records from the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract where parameter) or scalar
    arg 2: arrayref (SQL::Abstract order parameter) - optional
    
    dbi->table->read({
        'column_a' => 'value_a',
    });
    
    or
    
    dbi->table->read(1);
    
    # return arrayref from read (select) method
    my $records = dbi->table->read->collection

=head2 update

    The update method alters an existing record in the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract fields parameter)
    arg 2: arrayref (SQL::Abstract where parameter) or scalar - optional
    
    dbi->table->update({
        'column_a' => 'value_a',
    },{
        'where_column_a' => '...'
    });
    
    or
    
    dbi->table->update({
        'column_a' => 'value_a',
    }, 1);

=head2 delete

    The delete method is prohibited from deleting an entire database table and
    thus requires a where clause. If you intentionally desire to empty the entire
    database then you may use the delete_all method.
    
    dbi->table->delete({
        'column_a' => 'value_a',
    });
    
    or
    
    dbi->table->delete(1);

=head2 delete_all

    The delete_all method is use to intentionally empty the entire database table.
    
    dbi->table->delete_all;

=head1 RESULTSET METHODS

Dancer::Plugin::ORMesque provides columns accessors to the current record in the
resultset object which is accessible via current() by default, collection()
returns an arrayref of hashrefs based on the last read() call. Alternatively you
may use the following methods to further transform and manipulate the returned
resultset.

=head2 columns

    Returns a list of column names. In scalar context, returns an array reference.
    Column names are lower cased if lc_columns was true when the query was executed.

=head2 into

    Binds the columns returned from the query to variable(s)
    
    dbi->table->read(1)->into(my ($foo, $bar));

=head2 list

    Fetches a single row and returns a list of values. In scalar context,
    returns only the last value.
    
    my @values = dbi->table->read(1)->list;

=head2 array

    Fetches a single row and returns an array reference.
    
    my $row = dbi->table->read(1)->array;
    print $row->[0];

=head2 hash

    Fetches a single row and returns a hash reference.
    Keys are lower cased if lc_columns was true when the query was executed.
    
    my $row = dbi->table->read(1)->hash;
    print $row->{id};

=head2 flat

    Fetches all remaining rows and returns a flattened list.
    In scalar context, returns an array reference.
    
    my @records = dbi->table->read(1)->flat;
    print $records[0];

=head2 arrays

    Fetches all remaining rows and returns a list of array references.
    In scalar context, returns an array reference.
    
    my $rows = dbi->table->read(1)->arrays;
    print $rows->[0];

=head2 hashes

    Fetches all remaining rows and returns a list of hash references.
    In scalar context, returns an array reference.
    Keys are lower cased if lc_columns was true when the query was executed.
    
    my $rows = dbi->table->read(1)->hashes;
    print $rows->[0]->{id};

=head2 map_hashes

    Constructs a hash of hash references keyed by the values in the chosen column.
    In scalar context, returns a hash reference.
    In list context, returns interleaved keys and values.
    
    my $customer = dbi->table->read->map_hashes('id');
    # $customers = { $id => { name => $name, location => $location } }

=head2 map_arrays

    Constructs a hash of array references keyed by the values in the chosen column.
    In scalar context, returns a hash reference.
    In list context, returns interleaved keys and values.
    
    my $customer = dbi->table->read->map_arrays(0);
    # $customers = { $id => [ $name, $location ] }

=head2 rows

    Returns the number of rows affected by the last row affecting command,
    or -1 if the number of rows is not known or not available.
    For SELECT statements, it is generally not possible to know how many
    rows are returned. MySQL does provide this information. See DBI for a
    detailed explanation.
    
    my $changes = dbi->table->insert(dbi->table->current)->rows;

=head1 UTILITIES

Dancer::Plugin::ORMesque is a sub-class of L<DBIx::Simple> and uses L<SQL::Abstract>
as its querying language, it also provides access to L<SQL::Interp> for good measure.
For an in-depth look at what you can do with these utilities, please check out
l<DBIx::Simple::Examples>.

=head2 query

The query function provides a simplified interface to DBI, Perl's powerful
database interfacing module. This function provides auto-escaping/interpolation
as well as resultset abstraction.

    $db->query('DELETE FROM foo WHERE id = ?', $id);
    $db->query('SELECT 1 + 1')->into(my $two);
    $db->query('SELECT 3, 2 + 2')->into(my ($three, $four));

    $db->query(
        'SELECT name, email FROM people WHERE email = ? LIMIT 1',
        $mail
    )->into(my ($name, $email));
    
    # One big flattened list (primarily for single column queries)
    
    my @names = $db->query('SELECT name FROM people WHERE id > 5')->flat;
    
    # Rows as array references
    
    for my $row ($db->query('SELECT name, email FROM people')->arrays) {
        print "Name: $row->[0], Email: $row->[1]\n";
    }

=head2 iquery

The iquery function is used to interpolate Perl variables into SQL statements, it
converts a list of intermixed SQL fragments and variable references into a
conventional SQL string and list of bind values suitable for passing onto DBI

    my $result = $db->iquery('INSERT INTO table', \%item);
    my $result = $db->iquery('UPDATE table SET', \%item, 'WHERE y <> ', \2);
    my $result = $db->iquery('DELETE FROM table WHERE y = ', \2);

    # These two select syntax produce the same result
    my $result = $db->iquery('SELECT * FROM table WHERE x = ', \$s, 'AND y IN', \@v);
    my $result = $db->iquery('SELECT * FROM table WHERE', {x => $s, y => \@v});

    my $first_record = $result->hash;
    for ($result->hashes) { ... }

=head1 WHERE ART THOU JOINS?

If you have used Dancer::Plugin::ORMesque with a project of any sophistication
you will have undoubtedly noticed that the is no mechanism for specifying joins
and this is intentional. Dancer::Plugin::ORMesque is an ORM, and object relational
mapper and that is its purpose, it is not a SQL substitute. Joins are neccessary
in SQL as they are the only means of gathering related data. Such is not the case
with Perl code. The following is an example of gathering data using ORMesque...

    my $user = dbi->user->read->first;
    $user->{locations} = dbi->user_locations->read({ user => $user->id });
    return $user;

=head1 AUTHOR

Al Newkirk <awncorp@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by awncorp.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

