# frozen_string_literal: true

require "spec_helper"

describe ActiveRecall::Deck do
  let(:user) { User.create!(name: "Robert") }
  let(:word) do
    Word.create!(
      kanji: "日本語",
      kana: "にほんご",
      translation: "Japanese language"
    )
  end
  let(:other_word) do
    Word.create!(
      kanji: "日本語1",
      kana: "にほんご1",
      translation: "Japanese language"
    )
  end

  describe ".review" do
    subject { user.words.review }

    context "when configured with the FibonacciSequence" do
      let(:previous_algorithm) { ActiveRecall.configuration.algorithm_class }

      before do
        previous_algorithm
        ActiveRecall.configure do |config|
          config.algorithm_class = ActiveRecall::FibonacciSequence
        end
      end

      after do
        ActiveRecall.configure { |config| config.algorithm_class = previous_algorithm }
      end

      context "when a word is marked right a few times" do
        before do
          user.words << word
          3.times { user.right_answer_for!(word) }
        end

        it "doesn't include the card in review (because it is known)" do
          expect(user.words.review).not_to include(word)
        end

        context "but then is marked wrong" do
          before { user.wrong_answer_for!(word) }

          it "should include that word in review" do
            expect(user.words.review).to include(word)
          end
        end
      end
    end

    context "when configured with LeitnerSystem" do
      let(:previous_algorithm) { ActiveRecall.configuration.algorithm_class }

      before do
        previous_algorithm
        ActiveRecall.configure do |config|
          config.algorithm_class = ActiveRecall::LeitnerSystem
        end
      end

      after do
        ActiveRecall.configure { |config| config.algorithm_class = previous_algorithm }
      end

      it "should return an collection of words to review" do
        user.words << word
        user.words << other_word
        expect(user.words.known.count).to be_zero
        words = (user.words.untested + user.words.failed + user.words.expired).sort
        expect(words).to eq(subject.sort)
      end

      it "allows marking words right/wrong" do
        user.words << word
        user.words << other_word
        expect(user.words.count).to eq(2)
        expect(user.words.review.count).to eq(2)
        user.words.review.each_with_index do |word, index|
          index.even? ? user.right_answer_for!(word) : user.wrong_answer_for!(word)
        end
        expect(subject.count).to eq(1)
      end

      it "should allow you to get one word only" do
        user.words << word
        user.words << other_word
        expect(user.words.known.count).to be_zero
        word = user.words.next
        expect(user.words.untested).to include(word)
        user.right_answer_for!(word)
        word = user.words.next
        expect(user.words.untested).to include(word)
        user.right_answer_for!(word)
        expect(user.words.next).to_not be
      end

      it "returns a chainable relation" do
        user.words << word
        user.words << other_word
        user.words.each { |word| user.wrong_answer_for!(word) }
        relation = subject.where(kanji: word.kanji)
        expect(relation).to include(word)
        expect(relation).not_to include(other_word)
      end
    end
  end

  describe "#<<" do
    it "should add words to the word list" do
      user.words << word
      expect(user.words).to eq([word])
    end

    it "should raise an error if a duplicate word exists" do
      user.words << word
      expect(user.words).to eq([word])
      expect { user.words << word }.to raise_error(ArgumentError)
    end

    it "should tell you what word was last added to the deck" do
      user.words << word
      expect(user.words.last).to eq(word)
    end
  end

  describe "#each" do
    it "should be an iterator of words" do
      user.words << word

      collection = user.words.each_with_object([]) do |word, array|
        array << word
      end

      expect(collection).to eq([word])
    end
  end

  describe "#delete" do
    it "should remove words from the word list (but not destroy the source)" do
      expect(user.words).not_to include(word)
      user.words << word
      expect(user.words).to include(word)

      user.words.delete(word)

      expect(user.words).not_to include(word)
      expect(word).not_to be_destroyed
      expect(user).not_to be_destroyed
    end
  end

  describe "#destroy" do
    context "when there is a deck" do
      let(:deck) { user.words }

      it "should delete itself and all item information when the source model is deleted" do
        deck && user.destroy
        expect(ActiveRecall::Deck.exists?(user_id: user.id)).to be_falsey
        expect(ActiveRecall::Item.exists?(deck_id: deck.id)).to be_falsey
        expect(word).to_not be_destroyed
      end
    end

    context "before a deck has been created" do
      it "does not raise an error" do
        expect { user.destroy }.not_to raise_error
      end
    end
  end
end
