package Blog;
use Mojo::Base 'Mojolicious';

use Blog::Model::Posts;
use Mojo::mysql;

sub startup {
  my $self = shift;

  # Configuration
  $self->plugin('Config');
  $self->secrets($self->config('secrets'));

  # Model
  $self->helper(mysql => sub { state $mysql = Mojo::mysql->new(shift->config('mysql')) });
  $self->helper(
    posts => sub { state $posts = Blog::Model::Posts->new(mysql => shift->mysql) });

  # Migrate to latest version if necessary
  my $path = $self->home->rel_file('migrations/blog.sql');
  $self->mysql->migrations->name('blog')->from_file($path)->migrate;

  # Controller
  my $r = $self->routes;
  $r->get('/' => sub { shift->redirect_to('posts') });
  $r->get('/posts')->to('posts#index');
  $r->get('/posts/create')->to('posts#create')->name('create_post');
  $r->post('/posts')->to('posts#store')->name('store_post');
  $r->get('/posts/:id')->to('posts#show')->name('show_post');
  $r->get('/posts/:id/edit')->to('posts#edit')->name('edit_post');
  $r->put('/posts/:id')->to('posts#update')->name('update_post');
  $r->delete('/posts/:id')->to('posts#remove')->name('remove_post');
}

1;
