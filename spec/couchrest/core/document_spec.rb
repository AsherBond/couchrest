require File.dirname(__FILE__) + '/../../spec_helper'

describe CouchRest::Document, "[]=" do
  before(:each) do
    @doc = CouchRest::Document.new
  end
  it "should work" do
    @doc["enamel"].should == nil
    @doc["enamel"] = "Strong"
    @doc["enamel"].should == "Strong"
  end
  it "[]= should convert to string" do
    @doc["enamel"].should == nil
    @doc[:enamel] = "Strong"
    @doc["enamel"].should == "Strong"
  end
  it "should read as a string" do
    @doc[:enamel] = "Strong"
    @doc[:enamel].should == "Strong"
  end
end

describe CouchRest::Document, "new" do
  before(:each) do
    @doc = CouchRest::Document.new("key" => [1,2,3], :more => "values")    
  end
  it "should create itself from a Hash" do
    @doc["key"].should == [1,2,3]
    @doc["more"].should == "values"
  end
  it "should not have rev and id" do
    @doc.rev.should be_nil
    @doc.id.should be_nil
  end
  it "should freak out when saving without a database" do
    lambda{@doc.save}.should raise_error(ArgumentError)
  end
end

# move to database spec
describe CouchRest::Document, "saving using a database" do
  before(:all) do
    @doc = CouchRest::Document.new("key" => [1,2,3], :more => "values")    
    @db = reset_test_db!    
    @resp = @db.save_doc(@doc)
  end
  it "should apply the database" do
    @doc.database.should == @db    
  end
  it "should get id and rev" do
    @doc.id.should == @resp["id"]
    @doc.rev.should == @resp["rev"]
  end
end

describe CouchRest::Document, "bulk saving" do
  before :all do
    @db = reset_test_db!
  end

  it "should use the document bulk save cache" do
    doc = CouchRest::Document.new({"_id" => "bulkdoc", "val" => 3})
    doc.database = @db
    doc.save(true)
    lambda { doc.database.get(doc["_id"]) }.should raise_error(RestClient::ResourceNotFound)
    doc.database.bulk_save
    doc.database.get(doc["_id"])["val"].should == doc["val"]
  end
end

describe "getting from a database" do
  before(:all) do
    @db = reset_test_db!
    @resp = @db.save_doc({
      "key" => "value"
    })
    @doc = @db.get @resp['id']
  end
  it "should return a document" do
    @doc.should be_an_instance_of(CouchRest::Document)
  end
  it "should have a database" do
    @doc.database.should == @db
  end
  it "should be saveable and resavable" do
    @doc["more"] = "keys"
    @doc.save
    @db.get(@resp['id'])["more"].should == "keys"
    @doc["more"] = "these keys"    
    @doc.save
    @db.get(@resp['id'])["more"].should == "these keys"
  end
end

describe "destroying a document from a db" do
  before(:all) do
    @db = reset_test_db!
    @resp = @db.save_doc({
      "key" => "value"
    })
    @doc = @db.get @resp['id']
  end
  it "should make it disappear" do
    @doc.destroy
    lambda{@db.get @resp['id']}.should raise_error
  end
  it "should error when there's no db" do
    @doc = CouchRest::Document.new("key" => [1,2,3], :more => "values")    
    lambda{@doc.destroy}.should raise_error(ArgumentError)
  end
end


describe "destroying a document from a db using bulk save" do
  before(:all) do
    @db = reset_test_db!
    @resp = @db.save_doc({
      "key" => "value"
    })
    @doc = @db.get @resp['id']
  end
  it "should defer actual deletion" do
    @doc.destroy(true)
    @doc['_id'].should == nil
    @doc['_rev'].should == nil
    lambda{@db.get @resp['id']}.should_not raise_error
    @db.bulk_save
    lambda{@db.get @resp['id']}.should raise_error
  end
end

describe "copying a document" do
  before :each do
    @db = reset_test_db!
    @resp = @db.save_doc({'key' => 'value'})
    @docid = 'new-location'
    @doc = @db.get(@resp['id'])
  end
  describe "to a new location" do
    it "should work" do
      @doc.copy @docid
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
    end
    it "should fail without a database" do
      lambda{CouchRest::Document.new({"not"=>"a real doc"}).copy}.should raise_error(ArgumentError)
    end
  end
  describe "to an existing location" do
    before :each do
      @db.save_doc({'_id' => @docid, 'will-exist' => 'here'})
    end
    it "should fail without a rev" do
      lambda{@doc.copy @docid}.should raise_error(RestClient::RequestFailed)
    end
    it "should succeed with a rev" do
      @to_be_overwritten = @db.get(@docid)
      @doc.copy "#{@docid}?rev=#{@to_be_overwritten['_rev']}"
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
    end
    it "should succeed given the doc to overwrite" do
      @to_be_overwritten = @db.get(@docid)
      @doc.copy @to_be_overwritten
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
    end
  end
end

describe "MOVE existing document" do
  before :each do
    @db = reset_test_db!
    @resp = @db.save_doc({'key' => 'value'})
    @docid = 'new-location'
    @doc = @db.get(@resp['id'])
  end
  describe "to a new location" do
    it "should work" do
      @doc.move @docid
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
      lambda {@db.get(@resp['id'])}.should raise_error(RestClient::ResourceNotFound)
    end
    it "should fail without a database" do
      lambda{CouchRest::Document.new({"not"=>"a real doc"}).move}.should raise_error(ArgumentError)
      lambda{CouchRest::Document.new({"_id"=>"not a real doc"}).move}.should raise_error(ArgumentError)
    end
  end
  describe "to an existing location" do
    before :each do
      @db.save_doc({'_id' => @docid, 'will-exist' => 'here'})
    end
    it "should fail without a rev" do
      lambda{@doc.move @docid}.should raise_error(RestClient::RequestFailed)
      lambda{@db.get(@resp['id'])}.should_not raise_error
    end
    it "should succeed with a rev" do
      @to_be_overwritten = @db.get(@docid)
      @doc.move "#{@docid}?rev=#{@to_be_overwritten['_rev']}"
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
      lambda {@db.get(@resp['id'])}.should raise_error(RestClient::ResourceNotFound)
    end
    it "should succeed given the doc to overwrite" do
      @to_be_overwritten = @db.get(@docid)
      @doc.move @to_be_overwritten
      newdoc = @db.get(@docid)
      newdoc['key'].should == 'value'
      lambda {@db.get(@resp['id'])}.should raise_error(RestClient::ResourceNotFound)
    end
  end
end
