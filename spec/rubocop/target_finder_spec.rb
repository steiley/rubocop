# frozen_string_literal: true

RSpec.describe RuboCop::TargetFinder, :isolated_environment do
  include FileHelper

  ruby_extensions = %w[.rb
                       .arb
                       .axlsx
                       .builder
                       .fcgi
                       .gemfile
                       .gemspec
                       .god
                       .jb
                       .jbuilder
                       .mspec
                       .opal
                       .pluginspec
                       .podspec
                       .rabl
                       .rake
                       .rbuild
                       .rbw
                       .rbx
                       .ru
                       .ruby
                       .schema
                       .spec
                       .thor
                       .watchr]

  ruby_interpreters = %w[ruby macruby rake jruby rbx]

  ruby_filenames = %w[.irbrc
                      .pryrc
                      .simplecov
                      Appraisals
                      Berksfile
                      Brewfile
                      Buildfile
                      Capfile
                      Cheffile
                      Dangerfile
                      Deliverfile
                      Fastfile
                      Gemfile
                      Guardfile
                      Jarfile
                      Mavenfile
                      Podfile
                      Puppetfile
                      Rakefile
                      rakefile
                      Schemafile
                      Snapfile
                      Steepfile
                      Thorfile
                      Vagabondfile
                      Vagrantfile
                      buildfile]

  subject(:target_finder) { described_class.new(config_store, options) }

  let(:config_store) { RuboCop::ConfigStore.new }
  let(:options) do
    {
      force_exclusion: force_exclusion,
      ignore_parent_exclusion: ignore_parent_exclusion,
      debug: debug
    }
  end
  let(:force_exclusion) { false }
  let(:ignore_parent_exclusion) { false }
  let(:debug) { false }

  before do
    create_empty_file('dir1/ruby1.rb')
    create_empty_file('dir1/ruby2.rb')
    create_empty_file('dir1/file.txt')
    create_empty_file('dir1/file')
    create_file('dir1/executable', '#!/usr/bin/env ruby')
    create_empty_file('dir2/ruby3.rb')
    create_empty_file('.hidden/ruby4.rb')

    RuboCop::ConfigLoader.clear_options
  end

  shared_examples 'common behavior for #find' do
    context 'when a file with a ruby filename is passed' do
      let(:args) { ruby_filenames.map { |name| "dir2/#{name}" } }

      it 'picks all the ruby files' do
        expect(found_basenames).to eq(ruby_filenames)
      end
    end

    context 'when files with ruby interpreters are passed' do
      let(:args) { ruby_interpreters.map { |name| "dir2/#{name}" } }

      before do
        ruby_interpreters.each do |interpreter|
          create_file("dir2/#{interpreter}", "#!/usr/bin/#{interpreter}")
        end
      end

      it 'picks all the ruby files' do
        expect(found_basenames).to eq(ruby_interpreters)
      end
    end

    context 'when a pattern is passed' do
      let(:args) { ['dir1/*2.rb'] }

      it 'finds files which match the pattern' do
        expect(found_basenames).to eq(['ruby2.rb'])
      end
    end

    context 'when a pattern with matching folders is passed' do
      before { create_empty_file('app/dir.rb/ruby.rb') }

      let(:args) { ['app/**/*.rb'] }

      it 'finds only files which match the pattern' do
        expect(found_basenames).to eq(['ruby.rb'])
      end
    end

    context 'when same paths are passed' do
      let(:args) { %w[dir1 dir1] }

      it 'does not return duplicated file paths' do
        count = found_basenames.count { |f| f == 'ruby1.rb' }
        expect(count).to eq(1)
      end
    end

    context 'when some paths are specified in the configuration Exclude ' \
            'and they are explicitly passed as arguments' do
      before do
        create_file('.rubocop.yml', <<~YAML)
          AllCops:
            Exclude:
              - dir1/ruby1.rb
              - 'dir2/*'
        YAML

        create_file('dir1/.rubocop.yml', <<~YAML)
          AllCops:
            Exclude:
              - executable
        YAML
      end

      let(:args) { ['dir1/ruby1.rb', 'dir1/ruby2.rb', 'dir1/exe*', 'dir2/ruby3.rb'] }

      context 'normally' do
        it 'does not exclude them' do
          expect(found_basenames).to eq(['ruby1.rb', 'ruby2.rb', 'executable', 'ruby3.rb'])
        end
      end

      context "when it's forced to adhere file exclusion configuration" do
        let(:force_exclusion) { true }

        context 'when parent exclusion is in effect' do
          before do
            create_file('dir2/.rubocop.yml', <<~YAML)
              require:
                - unloadable_extension
            YAML
          end

          it 'excludes only files that are excluded on top level and does not load ' \
             'other configuration files unnecessarily' do
            expect(found_basenames).to eq(['ruby2.rb', 'executable'])
          end
        end

        context 'when parent exclusion is ignored' do
          let(:ignore_parent_exclusion) { true }

          it 'excludes files that are excluded on any level' do
            expect(found_basenames).to eq(['ruby2.rb'])
          end
        end
      end
    end

    it 'returns absolute paths' do
      expect(found_files).not_to be_empty
      found_files.each { |file| expect(Pathname.new(file)).to be_absolute }
    end

    it 'does not find hidden files' do
      expect(found_files).not_to include('.hidden/ruby4.rb')
    end

    context 'when no argument is passed' do
      let(:args) { [] }

      it 'finds files under the current directory' do
        Dir.chdir('dir1') do
          expect(found_files).not_to be_empty
          found_files.each do |file|
            expect(file).to include('/dir1/')
            expect(file).not_to include('/dir2/')
          end
        end
      end
    end

    context 'when a directory path is passed' do
      let(:args) { ['../dir2'] }

      it 'finds files under the specified directory' do
        Dir.chdir('dir1') do
          expect(found_files).not_to be_empty
          found_files.each do |file|
            expect(file).to include('/dir2/')
            expect(file).not_to include('/dir1/')
          end
        end
      end
    end

    context 'when a hidden directory path is passed' do
      let(:args) { ['.hidden'] }

      it 'finds files under the specified directory' do
        expect(found_files.size).to be(1)
        expect(found_files.first).to include('.hidden/ruby4.rb')
      end
    end

    context 'when some non-known Ruby files are specified in the ' \
            'configuration Include and they are explicitly passed ' \
            'as arguments' do
      before do
        create_file('.rubocop.yml', <<~YAML)
          AllCops:
            Include:
              - dir1/file
        YAML
      end

      let(:args) { ['dir1/file'] }

      it 'includes them' do
        expect(found_basenames).to contain_exactly('file')
      end
    end
  end

  shared_examples 'when input is passed on stdin' do
    context 'when input is passed on stdin' do
      let(:options) do
        {
          force_exclusion: force_exclusion,
          debug: debug,
          stdin: 'def example; end'
        }
      end
      let(:args) { ['Untitled'] }

      it 'includes the file' do
        expect(found_basenames).to eq(['Untitled'])
      end
    end
  end

  describe '#find(..., :only_recognized_file_types)' do
    let(:found_files) { target_finder.find(args, :only_recognized_file_types) }
    let(:found_basenames) { found_files.map { |f| File.basename(f) } }
    let(:args) { [] }

    context 'when a hidden directory path is passed' do
      let(:args) { ['.hidden'] }

      it 'finds files under the specified directory' do
        expect(found_files.size).to be(1)
        expect(found_files.first).to include('.hidden/ruby4.rb')
      end
    end

    context 'when a non-ruby file is passed' do
      let(:args) { ['dir2/file'] }

      it "doesn't pick the file" do
        expect(found_basenames).to be_empty
      end
    end

    context 'when files with a ruby extension are passed' do
      let(:args) { ruby_extensions.map { |ext| "dir2/file#{ext}" } }

      it 'picks all the ruby files' do
        expect(found_basenames).to eq(ruby_extensions.map { |ext| "file#{ext}" })
      end

      context 'when local AllCops/Include lists two patterns' do
        before do
          create_file('.rubocop.yml', <<~YAML)
            AllCops:
              Include:
                - '**/*.rb'
                - '**/*.arb'
          YAML
        end

        it 'picks two files' do
          expect(found_basenames).to eq(%w[file.rb file.arb])
        end

        context 'when a subdirectory AllCops/Include only lists one pattern' do
          before do
            create_file('dir2/.rubocop.yml', <<~YAML)
              AllCops:
                Include:
                  - '**/*.ruby'
            YAML
          end

          # Include and Exclude patterns are take from the top directory and
          # settings in subdirectories are silently ignored.
          it 'picks two files' do
            expect(found_basenames).to eq(%w[file.rb file.arb])
          end
        end
      end
    end

    include_examples 'common behavior for #find'

    context 'when some non-known Ruby files are specified in the ' \
            'configuration Include and they are not explicitly passed ' \
            'as arguments' do
      before do
        create_file('.rubocop.yml', <<~YAML)
          AllCops:
            Include:
              - '**/*.rb'
              - dir1/file
        YAML
      end

      let(:args) { ['dir1/**/*'] }

      it 'includes them' do
        expect(found_basenames).to contain_exactly('executable', 'file', 'ruby1.rb', 'ruby2.rb')
      end
    end

    include_examples 'when input is passed on stdin'
  end

  describe '#find(..., :all_file_types)' do
    let(:found_files) { target_finder.find(args, :all_file_types) }
    let(:found_basenames) { found_files.map { |f| File.basename(f) } }
    let(:args) { [] }

    include_examples 'common behavior for #find'

    context 'when a non-ruby file is passed' do
      let(:args) { ['dir2/file'] }

      it 'picks the file' do
        expect(found_basenames).to contain_exactly('file')
      end
    end

    context 'when files with a ruby extension are passed' do
      shared_examples 'picks all the ruby files' do
        it 'picks all the ruby files' do
          expect(found_basenames).to eq(ruby_extensions.map { |ext| "file#{ext}" })
        end
      end

      let(:args) { ruby_extensions.map { |ext| "dir2/file#{ext}" } }

      include_examples 'picks all the ruby files'

      context 'when local AllCops/Include lists two patterns' do
        before do
          create_file('.rubocop.yml', <<~YAML)
            AllCops:
              Include:
                - '**/*.rb'
                - '**/*.arb'
          YAML
        end

        include_examples 'picks all the ruby files'

        context 'when a subdirectory AllCops/Include only lists one pattern' do
          before do
            create_file('dir2/.rubocop.yml', <<~YAML)
              AllCops:
                Include:
                  - '**/*.ruby'
            YAML
          end

          include_examples 'picks all the ruby files'
        end
      end
    end

    context 'when some non-known Ruby files are specified in the ' \
            'configuration Include and they are not explicitly passed ' \
            'as arguments' do
      before do
        create_file('.rubocop.yml', <<~YAML)
          AllCops:
            Include:
              - '**/*.rb'
              - dir1/file
        YAML
      end

      let(:args) { ['dir1/**/*'] }

      it 'includes them' do
        expect(found_basenames).to contain_exactly('executable', 'file',
                                                   'file.txt', 'ruby1.rb',
                                                   'ruby2.rb')
      end
    end

    include_examples 'when input is passed on stdin'
  end

  describe '#find_files' do
    let(:found_files) { target_finder.find_files(base_dir, flags) }
    let(:found_basenames) { found_files.map { |f| File.basename(f) } }
    let(:base_dir) { Dir.pwd }
    let(:flags) { 0 }

    it 'does not search excluded top level directories' do
      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
    end

    it 'works also if a folder is named ","' do
      create_empty_file(',/ruby4.rb')

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
      expect(found_basenames).to include('ruby4.rb')
    end

    it 'works also if a folder is named "{}"' do
      create_empty_file('{}/ruby4.rb')

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
      expect(found_basenames).to include('ruby4.rb')
    end

    it 'works also if a folder is named "{foo}"' do
      create_empty_file('{foo}/ruby4.rb')

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
      expect(found_basenames).to include('ruby4.rb')
    end

    it 'works also if a folder is named "[...something]"' do
      create_empty_file('[...something]/ruby4.rb')

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
      expect(found_basenames).to include('ruby4.rb')
    end

    it 'works if patterns are empty' do
      allow(Dir).to receive(:glob).and_call_original
      allow_any_instance_of(described_class).to receive(:wanted_dir_patterns).and_return([])

      expect(Dir).to receive(:glob).with([File.join(base_dir, '**/*')], flags)
      expect(found_basenames).to include(
        'executable',
        'file.txt',
        'file',
        'ruby1.rb',
        'ruby2.rb',
        'ruby3.rb'
      )
    end

    # Cannot create a directory with containing `*` character on Windows.
    # https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#naming-conventions
    unless RuboCop::Platform.windows?
      it 'works also if a folder is named "**"' do
        create_empty_file('**/ruby5.rb')

        config = instance_double(RuboCop::Config)
        exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
        allow(config).to receive(:for_all_cops).and_return(exclude_property)
        allow(config_store).to receive(:for).and_return(config)

        expect(found_basenames).to include('ruby5.rb')
      end
    end

    it 'prevents infinite loops when traversing symlinks' do
      create_link('dir1/link/', File.expand_path('dir1'))

      expect(found_basenames).to include('ruby1.rb').once
    end

    it 'resolves symlinks when looking for excluded directories' do
      create_link('link', 'dir1')

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('dir1/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby1.rb')
      expect(found_basenames).to include('ruby3.rb')
    end

    it 'can exclude symlinks as well as directories' do
      create_empty_file(File.join(Dir.home, 'ruby5.rb'))
      create_link('link', Dir.home)

      config = instance_double(RuboCop::Config)
      exclude_property = { 'Exclude' => [File.expand_path('link/**/*')] }
      allow(config).to receive(:for_all_cops).and_return(exclude_property)
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby5.rb')
      expect(found_basenames).to include('ruby3.rb')
    end
  end

  describe '#target_files_in_dir' do
    let(:found_files) { target_finder.target_files_in_dir(base_dir) }
    let(:found_basenames) { found_files.map { |f| File.basename(f) } }
    let(:base_dir) { '.' }

    it 'picks files with extension .rb' do
      rb_file_count = found_files.count { |f| f.end_with?('.rb') }
      expect(rb_file_count).to eq(3)
    end

    it 'picks ruby executable files with no extension' do
      expect(found_basenames).to include('executable')
    end

    it 'does not pick files with no extension and no ruby shebang' do
      expect(found_basenames).not_to include('file')
    end

    it 'does not pick directories' do
      found_basenames = found_files.map { |f| File.basename(f) }
      allow(config_store).to receive(:for).and_return({})
      expect(found_basenames).not_to include('dir1')
    end

    it 'picks files specified to be included in config' do
      config = instance_double(RuboCop::Config)
      allow(config).to receive(:file_to_include?) do |file|
        File.basename(file) == 'file'
      end
      allow(config).to receive_messages(
        for_all_cops: { 'Exclude' => [], 'Include' => [], 'RubyInterpreters' => [] },
        :[] => [],
        file_to_exclude?: false
      )

      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).to include('file')
    end

    it 'does not pick files specified to be excluded in config' do
      config = instance_double(RuboCop::Config).as_null_object
      allow(config).to receive_messages(
        for_all_cops: { 'Exclude' => [], 'Include' => [], 'RubyInterpreters' => [] },
        file_to_include?: false
      )

      allow(config).to receive(:file_to_exclude?) do |file|
        File.basename(file) == 'ruby2.rb'
      end
      allow(config_store).to receive(:for).and_return(config)

      expect(found_basenames).not_to include('ruby2.rb')
    end

    context 'when an exception is raised while reading file' do
      include_context 'mock console output'

      before { allow_any_instance_of(File).to receive(:readline).and_raise(EOFError) }

      context 'and debug mode is enabled' do
        let(:debug) { true }

        it 'outputs error message' do
          found_files
          expect($stderr.string).to include('Unprocessable file')
        end
      end

      context 'and debug mode is disabled' do
        let(:debug) { false }

        it 'outputs nothing' do
          found_files
          expect($stderr.string).to be_empty
        end
      end
    end

    context 'when file is zero-sized' do
      include_context 'mock console output'

      before do
        create_file('dir1/flag', nil)
      end

      context 'and debug mode is enabled' do
        let(:debug) { true }

        it 'outputs error message' do
          found_files
          expect($stderr.string).to be_empty
        end
      end

      context 'and debug mode is disabled' do
        let(:debug) { false }

        it 'outputs nothing' do
          found_files
          expect($stderr.string).to be_empty
        end
      end
    end

    context 'when provided directory contains hidden segments' do
      let(:base_dir) { File.expand_path('.hidden') }

      it 'picks relevant files within provided directory' do
        expect(found_basenames).to match_array(%w[ruby4.rb])
      end

      context 'with nested hidden directory' do
        before do
          create_empty_file('.hidden/.nested-hidden/ruby5.rb')
          create_file('.hidden/shebang-ruby', '#! /usr/bin/env ruby')
          create_file('.hidden/shebang-zsh', '#! /usr/bin/env zsh')
        end

        it 'picks relevant files within provided directory' do
          expect(found_basenames).to match_array(%w[ruby4.rb ruby5.rb shebang-ruby])
        end
      end
    end

    context 'w/ --fail-fast option' do
      let(:options) { { force_exclusion: force_exclusion, debug: debug, fail_fast: true } }

      it 'works with the expected number of .rb files' do
        rb_file_count = found_files.count { |f| f.end_with?('.rb') }
        expect(rb_file_count).to eq(3)
      end
    end
  end
end
