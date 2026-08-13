require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const connectDB = require('../config/db');
const User = require('../models/User');

const createDeveloperUser = async () => {
    try {
        // Connect to database
        await connectDB();
        console.log('Connected to database');

        // Check if user already exists
        const existingUser = await User.findOne({ email: 'test1@gmail.com' });
        if (existingUser) {
            console.log('User already exists with email: test1@gmail.com');
            console.log('User ID:', existingUser._id);
            console.log('Role:', existingUser.role);
            process.exit(0);
        }

        // Create new user
        const user = await User.create({
            name: 'Developer',
            email: 'test1@gmail.com',
            password: '#India123',
            role: 'developer',
            isActive: true
        });

        console.log('✅ User created successfully!');
        console.log('User ID:', user._id);
        console.log('Email:', user.email);
        console.log('Role:', user.role);
        console.log('Name:', user.name);
        console.log('Is Active:', user.isActive);
        console.log('Password: #India123 (hashed automatically)');
        
        // Verify the user was saved
        const savedUser = await User.findById(user._id);
        if (savedUser) {
            console.log('\n✅ User verified in database!');
            console.log('Saved User Email:', savedUser.email);
            console.log('Saved User Role:', savedUser.role);
            
            // Test password matching
            const passwordMatch = await savedUser.matchPassword('#India123');
            console.log('Password Match Test:', passwordMatch ? '✅ CORRECT' : '❌ INCORRECT');
        } else {
            console.log('\n⚠️  Warning: User not found after creation');
        }
        
        process.exit(0);
    } catch (error) {
        console.error('❌ Error creating user:', error.message);
        if (error.code === 11000) {
            console.error('User with this email already exists');
        }
        process.exit(1);
    }
};

createDeveloperUser();
