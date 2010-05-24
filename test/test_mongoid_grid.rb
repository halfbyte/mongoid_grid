require 'test_helper'

class Asset
  include Mongoid::Document
  include Mongoid::Grid

  field :title, :type => String
  attachment :image
  attachment :file
end

class BaseModel
  include Mongoid::Document
  include Mongoid::Grid
  attachment :file
end

class Image < BaseModel; attachment :image end
class Video < BaseModel; attachment :video end

module Mongoid::GridTestHelpers
  def all_files
    [@file, @image, @image2, @test1, @test2]
  end

  def rewind_files
    all_files.each { |file| file.rewind }
  end

  def open_file(name)
    File.open(File.join(File.dirname(__FILE__), 'fixtures', name), 'r')
  end

  def grid
    @grid ||= Mongo::Grid.new(Mongoid.database)
  end
  
  def key_names
    [:id, :name, :type, :size]
  end
end

class Mongoid::GridTest < Test::Unit::TestCase
  include Mongoid::GridTestHelpers

  def setup
    super
    @file   = open_file('unixref.pdf')
    @image  = open_file('mr_t.jpg')
    @image2 = open_file('harmony.png')
    @test1  = open_file('test1.txt')
    @test2  = open_file('test2.txt')
  end

  def teardown
    all_files.each { |file| file.close }
  end

  context "Using Grid plugin" do
    should "add each attachment to attachment_types" do
      assert_equal [:image, :file], Asset.attachment_types
    end

    should "add keys for each attachment" do
      key_names.each do |key|
        assert Asset.fields.keys.include?("image_#{key}")
        assert Asset.fields.keys.include?("file_#{key}")
      end
    end

    context "with inheritance" do
      should "add attachment to attachment_types" do
        assert_equal [:file], BaseModel.attachment_types
      end

      should "inherit attachments from superclass, but not share other inherited class attachments" do
        assert_equal [:file, :image], Image.attachment_types
        assert_equal [:file, :video], Video.attachment_types
      end

      should "add inherit keys from superclass" do
        key_names.each do |key|
          assert BaseModel.fields.keys.include?("file_#{key}")
          assert Image.fields.keys.include?("file_#{key}") 
          assert Video.fields.keys.include?("file_#{key}")
          assert Video.fields.keys.include?("video_#{key}")
        end
      end
    end
  end

  context "Assigning new attachments to document" do
    setup do
      @doc = Asset.create(:image => @image, :file => @file)
      rewind_files
    end
    subject { @doc }

    should "assign GridFS content_type" do
      assert_equal 'image/jpeg', grid.get(subject.image_id).content_type
      assert_equal 'application/pdf', grid.get(subject.file_id).content_type
    end

    should "assign joint keys" do
      assert_equal 13661, subject.image_size
      assert_equal 68926, subject.file_size

      assert_equal "image/jpeg", subject.image_type
      assert_equal "application/pdf", subject.file_type

      assert_not_nil subject.image_id
      assert_not_nil subject.file_id

      assert subject.image_id.instance_of?(BSON::ObjectID)
      assert subject.file_id.instance_of?(BSON::ObjectID)
    end

    should "allow accessing keys through attachment proxy" do
      assert_equal 13661, subject.image_size 
      assert_equal 68926, subject.file_size

      assert_equal "image/jpeg", subject.image_type
      assert_equal "application/pdf", subject.file_type

      assert_not_nil subject.image_id
      assert_not_nil subject.file_id

      # assert subject.image.id.instance_of?(BSON::ObjectID),
      # assert subject.file.id.instance_of?(BSON::ObjectID)
    end

    should "proxy unknown methods to GridIO object" do
      assert_equal subject.image_id, subject.image.files_id
      assert_equal 'image/jpeg', subject.image.content_type
      assert_equal 'mr_t.jpg', subject.image.filename
      assert_equal 13661, subject.image.file_length
    end

    should "assign file name from path if original file name not available" do
      assert_equal 'mr_t.jpg', subject.image_name
      assert_equal 'unixref.pdf', subject.file_name
    end

    should "save attachment contents correctly" do
      assert_equal @file.read, subject.file.read
      assert_equal @image.read, subject.image.read
    end

    should "know that attachment exists" do
      assert subject.image?
      assert subject.file?
    end

    should "clear assigned attachments so they don't get uploaded twice" do
      Mongo::Grid.any_instance.expects(:put).never
      subject.save
    end
  end

  context "Updating existing attachment" do
    setup do
      @doc = Asset.create(:file => @test1)
      assert_no_grid_difference do
        @doc.file = @test2
        @doc.save!
      end
      rewind_files
    end
    subject { @doc }

    should "not change attachment id" do
      assert !subject.file_id_changed?
    end

    should "update keys" do
      assert_equal 'test2.txt', subject.file_name
      assert_equal "text/plain", subject.file_type
      assert_equal 5, subject.file_size 
    end

    should "update GridFS" do
      grid_obj = grid.get(subject.file_id)
      assert_equal 'test2.txt', grid_obj.filename
      assert_equal 'text/plain', grid_obj.content_type
      assert_equal 5, grid_obj.file_length
      assert_equal @test2.read, grid_obj.read
    end
  end

  context "Updating document but not attachments" do
    setup do
      @doc = Asset.create(:image => @image)
      @doc.update_attributes(:title => 'Updated')
      @doc.reload
      rewind_files
    end
    subject { @doc }

    should "not affect attachment" do
      assert_equal @image.read, subject.image.read
    end

    should "update document attributes" do
      assert_equal('Updated', subject.title)
    end
  end

  context "Assigning file where file pointer is not at beginning" do
    setup do
      @image.read
      @doc = Asset.create(:image => @image)
      @doc.reload
      rewind_files
    end
    subject { @doc }

    should "rewind and correctly store contents" do
      assert_equal @image.read, subject.image.read
    end
  end

  context "Setting attachment to nil" do
    setup do
      @doc = Asset.create(:image => @image)
      rewind_files
    end
    subject { @doc }

    should "delete attachment after save" do
      assert_no_grid_difference   { subject.image = nil }
      assert_grid_difference(-1)  { subject.save }
    end

    should "clear nil attachments after save and not attempt to delete again" do
      Mongo::Grid.any_instance.expects(:delete).once
      subject.image = nil
      subject.save
      Mongo::Grid.any_instance.expects(:delete).never
      subject.save
    end
  end

  context "Retrieving attachment that does not exist" do
    setup do
      @doc = Asset.create
      rewind_files
    end
    subject { @doc }

    should "know that the attachment is not present" do
      assert !subject.image?
    end

    # should "raise Mongo::GridFileNotFound" do
    #   assert_raises(Mongo::GridFileNotFound) { subject.image.read }
    # end
  end

  context "Destroying a document" do
    setup do
      @doc = Asset.create(:image => @image)
      rewind_files
    end
    subject { @doc }

    should "remove files from grid fs as well" do
      assert_grid_difference(-1) { subject.destroy }
    end
  end

  context "Assigning file name" do
    should "default to path" do
      assert_equal 'mr_t.jpg', Asset.create(:image => @image).image_name
    end

    should "use original_filename if available" do
      def @image.original_filename
        'testing.txt'
      end
      doc = Asset.create(:image => @image)
      assert_equal 'testing.txt', doc.image_name
    end
  end
end